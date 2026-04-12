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

def post_event(event_type, text="", reply=""):
    """Post voice event to kiosk for visual display."""
    try:
        data = json.dumps({"type": event_type, "text": text, "reply": reply}).encode()
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
        self._init_porcupine()

        # VAD for recording (not wake detection)
        import webrtcvad
        self.vad = webrtcvad.Vad(2)

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

    def send_to_codex(self, wav_path=None):
        """Send to Codex bridge. Returns reply text."""
        post_event("command", text="(thinking...)")

        persona = load_persona()
        persona_block = f"\n\n[PERSONA]\n{persona}\n[/PERSONA]\n" if persona else ""

        prompt = (
            "[Voice command from Alfredo kiosk mic] "
            "The user just spoke to you via the kiosk. "
            "Give a brief, useful response — one or two sentences max. "
            "This will be spoken aloud via TTS so keep it conversational and short. "
            "No emoji — this is for text-to-speech."
            f"{persona_block}"
        )

        try:
            data = json.dumps({"prompt": prompt}).encode()
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
        post_event("command", text="(thinking...)")
        LOG.info("Sending to Codex...")
        reply = self.send_to_codex(wav_path)

        # Speak reply
        post_event("reply", reply=reply)
        proc = self.tts.speak(reply)
        if proc:
            try:
                proc.wait(timeout=30)
            except subprocess.TimeoutExpired:
                proc.kill()

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
