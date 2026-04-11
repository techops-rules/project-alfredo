#!/usr/bin/env python3
"""
Alfredo Wake Word Listener

Listens on the ROADOM mic for voice activity, transcribes with Whisper,
and sends recognized speech to the alfredo bridge WebSocket.

Wake word: "alfredo" or "hey alfredo"
After wake word is detected, captures the following speech and sends it
to the bridge as a chat message.

Uses WebRTC VAD for voice activity detection and Whisper tiny.en for
fast local transcription.
"""

import asyncio
import json
import logging
import os
import struct
import tempfile
import time
import wave

import pyaudio
import webrtcvad
import whisper

LOG = logging.getLogger("alfredo-wake")

# Audio settings for WebRTC VAD (must be 16-bit, mono, 8/16/32kHz)
RATE = 16000
CHANNELS = 1
FRAME_DURATION_MS = 30  # 10, 20, or 30ms
FRAME_SIZE = int(RATE * FRAME_DURATION_MS / 1000)
FRAME_BYTES = FRAME_SIZE * 2  # 16-bit = 2 bytes per sample

# VAD sensitivity (0=least aggressive, 3=most aggressive filtering)
VAD_MODE = 2

# Wake word
WAKE_WORDS = ["alfredo", "hey alfredo", "alfred"]

# After wake word, how long to listen for the command (seconds)
COMMAND_TIMEOUT = 8.0

# Silence after speech to stop recording (seconds)
SILENCE_TIMEOUT = 1.5

BRIDGE_URL = "http://localhost:8420/chat"


class WakeListener:
    def __init__(self):
        self.vad = webrtcvad.Vad(VAD_MODE)
        self.model = None  # lazy load
        self.pa = pyaudio.PyAudio()

    def load_model(self):
        if self.model is None:
            LOG.info("Loading Whisper tiny.en model...")
            self.model = whisper.load_model("tiny.en")
            LOG.info("Whisper model loaded")

    def find_input_device(self):
        """Find the ROADOM mic or default input device."""
        info = self.pa.get_host_api_info_by_index(0)
        num_devices = info.get("deviceCount", 0)

        for i in range(num_devices):
            dev = self.pa.get_device_info_by_host_api_device_index(0, i)
            if dev.get("maxInputChannels", 0) > 0:
                name = dev.get("name", "")
                if "roadom" in name.lower() or "usb" in name.lower():
                    LOG.info("Found input device: %s (index %d)", name, i)
                    return i

        # Fall back to default
        default = self.pa.get_default_input_device_info()
        LOG.info("Using default input: %s", default.get("name", "unknown"))
        return default["index"]

    def record_frames(self, stream, max_seconds=10.0, silence_stop=True):
        """Record audio frames until silence or timeout."""
        frames = []
        voiced_count = 0
        silent_count = 0
        max_frames = int(max_seconds * 1000 / FRAME_DURATION_MS)
        silence_frames = int(SILENCE_TIMEOUT * 1000 / FRAME_DURATION_MS)

        for _ in range(max_frames):
            data = stream.read(FRAME_SIZE, exception_on_overflow=False)
            frames.append(data)

            is_speech = self.vad.is_speech(data, RATE)
            if is_speech:
                voiced_count += 1
                silent_count = 0
            else:
                silent_count += 1

            # Stop after sustained silence (only if we heard some speech)
            if silence_stop and voiced_count > 3 and silent_count > silence_frames:
                break

        return frames

    def frames_to_wav(self, frames):
        """Write frames to a temporary WAV file for Whisper."""
        tmp = tempfile.NamedTemporaryFile(suffix=".wav", delete=False)
        with wave.open(tmp.name, "wb") as wf:
            wf.setnchannels(CHANNELS)
            wf.setsampwidth(2)
            wf.setframerate(RATE)
            wf.writeframes(b"".join(frames))
        return tmp.name

    def transcribe(self, wav_path):
        """Transcribe a WAV file with Whisper."""
        self.load_model()
        result = self.model.transcribe(
            wav_path,
            language="en",
            fp16=False,  # Pi doesn't have GPU
        )
        text = result.get("text", "").strip()
        os.unlink(wav_path)
        return text

    def is_wake_word(self, text):
        """Check if transcribed text contains the wake word."""
        lower = text.lower()
        for wake in WAKE_WORDS:
            if wake in lower:
                # Return the text after the wake word
                idx = lower.index(wake) + len(wake)
                remainder = text[idx:].strip()
                return True, remainder
        return False, ""

    def send_to_bridge(self, text):
        """Send recognized text to the alfredo bridge via HTTP."""
        import httpx
        try:
            response = httpx.post(
                BRIDGE_URL,
                json={"prompt": text},
                timeout=120.0,
            )
            if response.status_code == 200:
                data = response.json()
                reply = data.get("response", "(no response)")
                LOG.info("Bridge reply: %s", reply[:100])
                # TODO: TTS the reply back through speakers
                return reply
            else:
                LOG.error("Bridge returned %d", response.status_code)
        except Exception as e:
            LOG.error("Bridge send failed: %s", e)
        return None

    def run(self):
        """Main listen loop."""
        self.load_model()
        device_idx = self.find_input_device()

        stream = self.pa.open(
            format=pyaudio.paInt16,
            channels=CHANNELS,
            rate=RATE,
            input=True,
            input_device_index=device_idx,
            frames_per_buffer=FRAME_SIZE,
        )

        LOG.info("Listening for wake word...")

        try:
            while True:
                # Phase 1: Listen for voice activity (low power)
                data = stream.read(FRAME_SIZE, exception_on_overflow=False)
                if not self.vad.is_speech(data, RATE):
                    continue

                # Phase 2: We heard something. Record a short clip.
                LOG.debug("Voice detected, recording snippet...")
                frames = [data]
                frames.extend(self.record_frames(stream, max_seconds=3.0))
                wav_path = self.frames_to_wav(frames)
                text = self.transcribe(wav_path)

                if not text:
                    continue

                LOG.info("Heard: %s", text)

                # Phase 3: Check for wake word
                is_wake, remainder = self.is_wake_word(text)
                if not is_wake:
                    continue

                LOG.info("Wake word detected!")

                if remainder:
                    # Wake word + command in same utterance
                    LOG.info("Command: %s", remainder)
                    self.send_to_bridge(remainder)
                else:
                    # Wait for the actual command
                    # TODO: play a "listening" chime
                    LOG.info("Listening for command...")
                    cmd_frames = self.record_frames(
                        stream, max_seconds=COMMAND_TIMEOUT
                    )
                    if cmd_frames:
                        wav_path = self.frames_to_wav(cmd_frames)
                        command = self.transcribe(wav_path)
                        if command:
                            LOG.info("Command: %s", command)
                            self.send_to_bridge(command)
                        else:
                            LOG.info("No command detected after wake word")

        except KeyboardInterrupt:
            LOG.info("Shutting down")
        finally:
            stream.stop_stream()
            stream.close()
            self.pa.terminate()


if __name__ == "__main__":
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(name)s] %(levelname)s %(message)s",
    )
    listener = WakeListener()
    listener.run()
