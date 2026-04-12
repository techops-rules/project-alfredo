#!/usr/bin/env python3
"""
Alfredo Voice — Porcupine wake word + Piper TTS + push-to-talk.

Two activation modes:
  1. Wake word "alfredo" (or fallback "jarvis") via Porcupine
  2. Push-to-talk via kiosk/phone button (POST /proxy/voice-activate)

Flow: wake → snarky ack → record command → send to Codex → speak reply
TTS: Piper neural voices (sounds human, runs locally on Pi)

Dependencies:
  pip: pvporcupine, piper-tts, webrtcvad, pyaudio
  apt: espeak-ng (fallback TTS only)
  env: PICOVOICE_ACCESS_KEY (get free at picovoice.ai)
"""

import json
import logging
import os
import random
import struct
import subprocess
import tempfile
import time
import wave
import uuid
from urllib.request import Request, urlopen

import pyaudio

LOG = logging.getLogger("alfredo-wake")

# ── Audio settings ──────────────────────────────────────────
MIC_RATE = 44100   # USB mic native rate
CHANNELS = 1

# ── Porcupine ───────────────────────────────────────────────
PICOVOICE_KEY = os.environ.get("PICOVOICE_ACCESS_KEY", "")
# Custom .ppn file for "alfredo" — train at console.picovoice.ai
CUSTOM_KEYWORD_PATH = os.path.expanduser("~/alfredo-kiosk/alfredo_wake.ppn")
FALLBACK_KEYWORD = "jarvis"  # built-in keyword if no custom .ppn

# ── Piper TTS ───────────────────────────────────────────────
# Download a voice: piper --download-dir ~/piper-voices -m en_US-lessac-medium
PIPER_MODEL = os.environ.get(
    "PIPER_MODEL",
    os.path.expanduser("~/piper-voices/en_US-lessac-medium.onnx")
)

# ── Timing ──────────────────────────────────────────────────
COMMAND_TIMEOUT = 8.0   # max seconds to record after wake
SILENCE_TIMEOUT = 1.5   # silence to stop recording
COOLDOWN = 3.0          # min seconds between wake triggers
WHISPER_MODEL = os.environ.get("WHISPER_MODEL", "tiny.en")
DIRECT_IDLE_TIMEOUT = 5 * 60

# ── Endpoints ───────────────────────────────────────────────
BRIDGE_URL = "http://localhost:8420/chat"
KIOSK_URL = "http://localhost:8430"

# ── Persona ────────────────────────────────────────────────
PERSONA_PATH = os.path.expanduser("~/alfredo-kiosk/persona.md")

def load_persona():
    """Load persona profile from markdown file. Returns persona text or default."""
    try:
        with open(PERSONA_PATH, "r") as f:
            return f.read()
    except FileNotFoundError:
        LOG.warning("No persona file at %s — using defaults", PERSONA_PATH)
        return ""

# ── Personality ─────────────────────────────────────────────
WAKE_ACKS = [
    "yeah?",
    "what's up?",
    "go ahead.",
    "listening.",
    "I'm here.",
    "shoot.",
    "what do you need?",
    "talk to me.",
    "ready.",
    "hmm?",
]

IDLE_QUIPS = [
    "nothing? okay.",
    "I'll be here.",
    "just say the word.",
]

SHUTUP_QUIPS = [
    "fine.",
    "okay, shutting up.",
    "got it, going quiet.",
]

DIRECT_START_PHRASES = [
    "talk to alfredo",
    "direct mode",
    "i need to talk to alfredo",
    "let me talk to alfredo",
]

DIRECT_STOP_PHRASES = [
    "stop",
    "that's enough",
    "thats enough",
    "got it",
    "thank you",
    "thanks",
]


# ── Audio helpers ───────────────────────────────────────────

def downsample(data_bytes, from_rate, to_rate):
    """Downsample 16-bit mono PCM by decimation."""
    samples = struct.unpack(f"<{len(data_bytes)//2}h", data_bytes)
    ratio = from_rate / to_rate
    out = []
    i = 0.0
    while int(i) < len(samples):
        out.append(samples[int(i)])
        i += ratio
    return struct.pack(f"<{len(out)}h", *out)


def resample_for_porcupine(data_bytes, from_rate, to_rate, target_samples):
    """Resample to exactly target_samples for Porcupine frame."""
    samples = struct.unpack(f"<{len(data_bytes)//2}h", data_bytes)
    ratio = from_rate / to_rate
    out = []
    i = 0.0
    while int(i) < len(samples) and len(out) < target_samples:
        out.append(samples[int(i)])
        i += ratio
    # Pad if short
    while len(out) < target_samples:
        out.append(0)
    return out[:target_samples]


# ── TTS ─────────────────────────────────────────────────────

class TTS:
    """Piper neural TTS with espeak-ng fallback."""

    def __init__(self):
        self._has_piper = os.path.exists(PIPER_MODEL)
        if self._has_piper:
            LOG.info("Piper TTS: %s", PIPER_MODEL)
        else:
            LOG.warning("Piper model not found at %s — will try downloading", PIPER_MODEL)
            self._try_download_piper()

    def _try_download_piper(self):
        """Try to download the default Piper voice model."""
        model_dir = os.path.dirname(PIPER_MODEL)
        os.makedirs(model_dir, exist_ok=True)
        try:
            LOG.info("Downloading Piper voice model...")
            subprocess.run(
                ["piper", "--download-dir", model_dir,
                 "-m", "en_US-lessac-medium", "--update-voices",
                 "--sentence_silence", "0.1",
                 "--output_file", "/dev/null"],
                input=b"test",
                capture_output=True, timeout=120,
            )
            self._has_piper = os.path.exists(PIPER_MODEL)
            if self._has_piper:
                LOG.info("Piper voice downloaded successfully")
            else:
                LOG.warning("Piper download didn't produce expected model file")
        except Exception as e:
            LOG.warning("Piper download failed: %s — falling back to espeak-ng", e)

    def speak(self, text):
        """Speak text. Returns subprocess.Popen for interrupt support."""
        if self._has_piper:
            return self._speak_piper(text)
        return self._speak_espeak(text)

    def _speak_piper(self, text):
        """Piper: text → WAV → aplay."""
        try:
            tmp = tempfile.NamedTemporaryFile(suffix=".wav", delete=False)
            tmp.close()
            # Piper generates WAV from stdin text
            subprocess.run(
                ["piper", "-m", PIPER_MODEL,
                 "--sentence_silence", "0.1",
                 "--output_file", tmp.name],
                input=text.encode(),
                capture_output=True, timeout=30,
            )
            # Play the WAV
            proc = subprocess.Popen(
                ["aplay", "-q", tmp.name],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            )
            # Clean up after playback (in background)
            def cleanup():
                proc.wait()
                try:
                    os.unlink(tmp.name)
                except Exception:
                    pass
            import threading
            threading.Thread(target=cleanup, daemon=True).start()
            return proc
        except Exception as e:
            LOG.warning("Piper TTS failed: %s", e)
            return self._speak_espeak(text)

    def _speak_espeak(self, text):
        """Fallback: espeak-ng."""
        try:
            return subprocess.Popen(
                ["espeak-ng", "-v", "en-us", "-s", "160", "-p", "30", text],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            )
        except Exception as e:
            LOG.warning("espeak-ng failed: %s", e)
            return None

    def speak_and_wait(self, text):
        proc = self.speak(text)
        if proc:
            try:
                proc.wait(timeout=20)
            except subprocess.TimeoutExpired:
                proc.kill()


# ── Kiosk integration ───────────────────────────────────────

def post_event(event_type, text="", reply="", mode="voice", session_id=None, session_state=None):
    """Post voice event to kiosk for visual display."""
    try:
        data = json.dumps({
            "type": event_type,
            "text": text,
            "reply": reply,
            "mode": mode,
            "session_id": session_id,
            "surface": "kiosk",
            "session_state": session_state,
        }).encode()
        req = Request(f"{KIOSK_URL}/proxy/voice-event", data=data,
                      headers={"Content-Type": "application/json"})
        urlopen(req, timeout=3)
    except Exception:
        pass


def is_muted():
    try:
        with urlopen(f"{KIOSK_URL}/proxy/voice-mute", timeout=2) as r:
            return json.loads(r.read()).get("muted", False)
    except Exception:
        return False


def check_push_to_talk():
    """Check if push-to-talk was activated from kiosk/phone."""
    try:
        with urlopen(f"{KIOSK_URL}/proxy/voice-activate", timeout=1) as r:
            data = json.loads(r.read())
            return data.get("active", False)
    except Exception:
        return False


def clear_push_to_talk():
    try:
        data = json.dumps({"active": False}).encode()
        req = Request(f"{KIOSK_URL}/proxy/voice-activate", data=data,
                      headers={"Content-Type": "application/json"})
        urlopen(req, timeout=1)
    except Exception:
        pass


# ── Main listener ───────────────────────────────────────────

class AlfredoVoice:
    def __init__(self):
        self.pa = pyaudio.PyAudio()
        self.tts = TTS()
        self.last_wake = 0
        self.porcupine = None
        self.whisper_model = None
        self._init_porcupine()

        # VAD for recording (not wake detection)
        import webrtcvad
        self.vad = webrtcvad.Vad(2)
        self.direct_session_id = None
        self.direct_expires_at = 0
        self.direct_history = []

    def _init_porcupine(self):
        """Initialize Porcupine wake word engine."""
        if not PICOVOICE_KEY:
            LOG.warning("No PICOVOICE_ACCESS_KEY — wake word disabled, push-to-talk only")
            return

        try:
            import pvporcupine
            if os.path.exists(CUSTOM_KEYWORD_PATH):
                LOG.info("Using custom wake word: %s", CUSTOM_KEYWORD_PATH)
                self.porcupine = pvporcupine.create(
                    access_key=PICOVOICE_KEY,
                    keyword_paths=[CUSTOM_KEYWORD_PATH],
                )
            else:
                LOG.info("Using built-in wake word: %s", FALLBACK_KEYWORD)
                self.porcupine = pvporcupine.create(
                    access_key=PICOVOICE_KEY,
                    keywords=[FALLBACK_KEYWORD],
                )
            LOG.info("Porcupine initialized (frame_length=%d, sample_rate=%d)",
                     self.porcupine.frame_length, self.porcupine.sample_rate)
        except Exception as e:
            LOG.error("Porcupine init failed: %s — push-to-talk only", e)

    def find_input_device(self):
        info = self.pa.get_host_api_info_by_index(0)
        for i in range(info.get("deviceCount", 0)):
            dev = self.pa.get_device_info_by_host_api_device_index(0, i)
            if dev.get("maxInputChannels", 0) > 0:
                name = dev.get("name", "")
                if "usb" in name.lower() or "roadom" in name.lower():
                    LOG.info("Mic: %s (index %d)", name, i)
                    return i
        default = self.pa.get_default_input_device_info()
        LOG.info("Mic: %s (default)", default.get("name", "unknown"))
        return default["index"]

    def record_command(self, stream):
        """Record speech after wake. Returns WAV path or None."""
        frames = []
        voiced = 0
        silent = 0
        vad_rate = 16000
        vad_frame = int(vad_rate * 30 / 1000)  # 480 samples
        max_frames = int(COMMAND_TIMEOUT * 1000 / 30)
        silence_frames = int(SILENCE_TIMEOUT * 1000 / 30)
        mic_frame = int(MIC_RATE * 30 / 1000)

        for _ in range(max_frames):
            data = stream.read(mic_frame, exception_on_overflow=False)
            frames.append(data)

            vad_data = downsample(data, MIC_RATE, vad_rate)
            expected = vad_frame * 2
            vad_data = vad_data[:expected].ljust(expected, b'\x00')

            if self.vad.is_speech(vad_data, vad_rate):
                voiced += 1
                silent = 0
            else:
                silent += 1

            if voiced > 3 and silent > silence_frames:
                break

        if voiced < 5:
            return None

        tmp = tempfile.NamedTemporaryFile(suffix=".wav", delete=False)
        with wave.open(tmp.name, "wb") as wf:
            wf.setnchannels(CHANNELS)
            wf.setsampwidth(2)
            wf.setframerate(MIC_RATE)
            wf.writeframes(b"".join(frames))
        return tmp.name

    def transcribe_command(self, wav_path):
        """Transcribe recorded speech to text with Whisper."""
        try:
            if self.whisper_model is None:
                LOG.info("Loading Whisper model: %s", WHISPER_MODEL)
                import whisper
                self.whisper_model = whisper.load_model(WHISPER_MODEL)

            result = self.whisper_model.transcribe(
                wav_path,
                language="en",
                fp16=False,
                verbose=False,
            )
            text = (result.get("text") or "").strip()
            if text:
                LOG.info("Transcript: %s", text[:120])
            return text
        except Exception as e:
            LOG.error("Whisper transcription failed: %s", e)
            return ""

    def fetch_direct_context(self):
        """Fetch kiosk-side context snapshot for direct mode prompts."""
        try:
            with urlopen(f"{KIOSK_URL}/proxy/direct-context", timeout=3) as r:
                data = json.loads(r.read())
        except Exception as e:
            LOG.warning("Direct context fetch failed: %s", e)
            return ""

        work = [t.get("text", "") for t in data.get("workTasks", [])[:5] if t.get("text")]
        life = [t.get("text", "") for t in data.get("lifeTasks", [])[:5] if t.get("text")]
        scratch = [line for line in data.get("scratch", [])[:4] if line]
        calendar_items = []
        for event in data.get("calendar", [])[:8]:
            title = event.get("title", "")
            start = event.get("startTime", "")
            location = event.get("location", "")
            if start:
                start = start[11:16] if "T" in start else start
            calendar_items.append(f"- {start} {title}" + (f" @ {location}" if location else ""))

        return (
            "[KIOSK DIRECT CONTEXT]\n"
            + "Calendar:\n" + ("\n".join(calendar_items) if calendar_items else "No events cached.") + "\n\n"
            + "Work tasks:\n" + ("\n".join(f"- {item}" for item in work) if work else "No work tasks cached.") + "\n\n"
            + "Life tasks:\n" + ("\n".join(f"- {item}" for item in life) if life else "No life tasks cached.") + "\n\n"
            + "Scratchpad:\n" + ("\n".join(f"- {item}" for item in scratch) if scratch else "No scratch notes cached.") + "\n"
            + "[/KIOSK DIRECT CONTEXT]"
        )

    def is_direct_active(self):
        return self.direct_session_id is not None and time.time() < self.direct_expires_at

    def extend_direct_session(self):
        if self.direct_session_id:
            self.direct_expires_at = time.time() + DIRECT_IDLE_TIMEOUT

    def begin_direct_session(self, transcript):
        if self.direct_session_id is None:
            self.direct_session_id = str(uuid.uuid4())
            self.direct_history = []
            LOG.info("Direct mode started: %s", self.direct_session_id)
            post_event(
                "session",
                text="direct mode active",
                mode="direct",
                session_id=self.direct_session_id,
                session_state="listening",
            )
        self.extend_direct_session()

    def close_direct_session(self, reason="direct mode closed"):
        if not self.direct_session_id:
            return
        session_id = self.direct_session_id
        self.direct_session_id = None
        self.direct_expires_at = 0
        self.direct_history = []
        LOG.info("Direct mode ended: %s", session_id)
        post_event(
            "dismissed",
            text=reason,
            mode="direct",
            session_id=session_id,
            session_state="closing",
        )

    def normalize_transcript(self, transcript):
        return transcript.lower().strip()

    def is_direct_start_phrase(self, transcript):
        normalized = self.normalize_transcript(transcript)
        return any(phrase in normalized for phrase in DIRECT_START_PHRASES)

    def is_direct_invocation_only(self, transcript):
        normalized = self.normalize_transcript(transcript)
        invocation_only = {
            "talk to alfredo",
            "direct mode",
            "i need to talk to alfredo",
            "let me talk to alfredo",
        }
        return normalized in invocation_only

    def is_direct_stop_phrase(self, transcript):
        normalized = self.normalize_transcript(transcript)
        return any(phrase in normalized for phrase in DIRECT_STOP_PHRASES)

    def send_to_codex(self, transcript, wav_path=None, direct_mode=False):
        """Send the transcribed voice command to the Codex agent bridge."""
        mode = "direct" if direct_mode else "voice"
        post_event(
            "command",
            text=transcript,
            mode=mode,
            session_id=self.direct_session_id,
            session_state="thinking",
        )

        persona = load_persona()
        persona_block = f"\n\n[PERSONA]\n{persona}\n[/PERSONA]\n" if persona else ""
        direct_context = self.fetch_direct_context() if direct_mode else ""
        history_block = ""
        if direct_mode and self.direct_history:
            history_block = "[DIRECT HISTORY]\n" + "\n".join(self.direct_history[-8:]) + "\n[/DIRECT HISTORY]\n"

        prompt = (
            "[Voice command from Alfredo kiosk mic] "
            + ("[DIRECT MODE ACTIVE] Stay in the same short conversation unless the user ends it.\n" if direct_mode else "")
            + f'The user said: "{transcript}"\n\n'
            "Respond to the user's actual spoken request. "
            "Give a brief, useful response — one or two sentences max. "
            "This will be spoken aloud via TTS so keep it conversational and short. "
            "No emoji — this is for text-to-speech."
            + ("\nUse the kiosk direct context below when it helps.\n" if direct_mode else "")
            + history_block
            + (direct_context + "\n" if direct_mode and direct_context else "")
            + persona_block
        )

        try:
            data = json.dumps({
                "prompt": prompt,
                "mode": "agent",
                "conversation_mode": "direct" if direct_mode else "voice",
                "session_id": self.direct_session_id,
            }).encode()
            req = Request(BRIDGE_URL, data=data,
                          headers={"Content-Type": "application/json"})
            with urlopen(req, timeout=60) as r:
                result = json.loads(r.read())
            reply = result.get("response", "Sorry, I got nothing.")
            # Trim to first 2 sentences for TTS
            sentences = reply.replace("...", ".").split(". ")
            reply = ". ".join(sentences[:2])
            if not reply.endswith("."):
                reply += "."
            LOG.info("Codex: %s", reply[:80])
            if direct_mode:
                self.direct_history.append(f"user: {transcript}")
                self.direct_history.append(f"assistant: {reply}")
                self.extend_direct_session()
            return reply
        except Exception as e:
            LOG.error("Codex failed: %s", e)
            return "Sorry, couldn't reach Codex."
        finally:
            if wav_path:
                try:
                    os.unlink(wav_path)
                except Exception:
                    pass

    def handle_wake(self, stream):
        """Full wake interaction: ack → record → codex → reply."""
        now = time.time()
        if now - self.last_wake < COOLDOWN:
            return
        self.last_wake = now

        if is_muted():
            LOG.info("Muted — ignoring")
            return

        LOG.info("Wake!")

        # Quick ack
        ack = random.choice(WAKE_ACKS)
        post_event("wake", text=ack)
        self.tts.speak_and_wait(ack)

        # Record command
        post_event("listening")
        LOG.info("Recording...")
        wav_path = self.record_command(stream)

        if not wav_path:
            quip = random.choice(IDLE_QUIPS)
            post_event("idle", text=quip)
            self.tts.speak_and_wait(quip)
            return

        # Send to Codex
        transcript = self.transcribe_command(wav_path)
        if not transcript:
            quip = "I didn't catch that. Try again."
            post_event("idle", text=quip, mode="direct" if self.is_direct_active() else "voice", session_id=self.direct_session_id)
            self.tts.speak_and_wait(quip)
            try:
                os.unlink(wav_path)
            except Exception:
                pass
            return

        starting_direct = self.is_direct_start_phrase(transcript)
        if starting_direct:
            self.begin_direct_session(transcript)
            if self.is_direct_invocation_only(transcript):
                reply = "Direct mode is active. Go ahead."
                post_event(
                    "reply",
                    reply=reply,
                    mode="direct",
                    session_id=self.direct_session_id,
                    session_state="speaking",
                )
                self.tts.speak_and_wait(reply)
                self.extend_direct_session()
                try:
                    os.unlink(wav_path)
                except Exception:
                    pass
                return

        if self.is_direct_active() and self.is_direct_stop_phrase(transcript):
            quip = random.choice(SHUTUP_QUIPS)
            self.close_direct_session("direct mode closed")
            self.tts.speak_and_wait(quip)
            return

        if self.is_direct_active():
            post_event(
                "session",
                text="direct mode listening",
                mode="direct",
                session_id=self.direct_session_id,
                session_state="listening",
            )

        LOG.info("Sending to Codex...")
        reply = self.send_to_codex(transcript, wav_path, direct_mode=self.is_direct_active())

        # Speak reply
        post_event(
            "reply",
            reply=reply,
            mode="direct" if self.is_direct_active() else "voice",
            session_id=self.direct_session_id,
            session_state="speaking" if self.is_direct_active() else None,
        )
        proc = self.tts.speak(reply)
        if proc:
            try:
                proc.wait(timeout=30)
            except subprocess.TimeoutExpired:
                proc.kill()

        if self.is_direct_active():
            self.extend_direct_session()

    def run(self):
        device_idx = self.find_input_device()

        stream = self.pa.open(
            format=pyaudio.paInt16,
            channels=CHANNELS,
            rate=MIC_RATE,
            input=True,
            input_device_index=device_idx,
            frames_per_buffer=1024,
        )

        porcupine_rate = self.porcupine.sample_rate if self.porcupine else 16000
        porcupine_frame = self.porcupine.frame_length if self.porcupine else 512
        # How many mic samples to read per Porcupine frame
        mic_samples_per_frame = int(MIC_RATE * porcupine_frame / porcupine_rate)

        mode = "porcupine" if self.porcupine else "push-to-talk only"
        keyword = "custom" if os.path.exists(CUSTOM_KEYWORD_PATH) else FALLBACK_KEYWORD
        LOG.info("Ready — mode: %s, keyword: %s", mode, keyword if self.porcupine else "n/a")
        LOG.info("Push-to-talk always available via kiosk mic button")

        try:
            while True:
                if self.direct_session_id and not self.is_direct_active():
                    self.close_direct_session("direct mode closed")

                # Check push-to-talk from kiosk/phone
                if check_push_to_talk():
                    clear_push_to_talk()
                    LOG.info("Push-to-talk activated")
                    self.handle_wake(stream)
                    continue

                if not self.porcupine:
                    # No wake word engine — just poll push-to-talk
                    time.sleep(0.5)
                    continue

                # Read audio for Porcupine
                data = stream.read(mic_samples_per_frame, exception_on_overflow=False)

                # Resample to Porcupine's expected rate
                pcm = resample_for_porcupine(
                    data, MIC_RATE, porcupine_rate, porcupine_frame
                )

                result = self.porcupine.process(pcm)
                if result >= 0:
                    LOG.info("Wake word detected (keyword_index=%d)", result)
                    self.handle_wake(stream)

        except KeyboardInterrupt:
            LOG.info("Shutting down")
        finally:
            stream.stop_stream()
            stream.close()
            self.pa.terminate()
            if self.porcupine:
                self.porcupine.delete()


if __name__ == "__main__":
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(name)s] %(message)s",
    )
    AlfredoVoice().run()
