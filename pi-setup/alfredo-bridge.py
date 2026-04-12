#!/usr/bin/env python3
"""
Alfredo Bridge v3 — WebSocket + HTTP server for interactive Claude Code.

Endpoints:
  GET  /health         → 200 OK (HTTP, for connection monitoring)
  POST /chat           → one-shot mode (HTTP, backward compat)
  POST /register-push  → store APNs device token
  WS   /ws             → interactive PTY session (WebSocket)

The WebSocket endpoint spawns `claude` in a PTY and streams I/O bidirectionally.
One claude process per WebSocket connection, killed on disconnect.

Agent mode: when init message includes "mode":"agent", spawns claude with
the Codex system prompt from ~/alfredo-kiosk/agent-prompt.txt.
"""

import asyncio
import json
import logging
import os
import pty
import signal
import struct
import fcntl
import termios
import subprocess
from http.server import HTTPServer, BaseHTTPRequestHandler
from threading import Thread

import websockets
from websockets.asyncio.server import serve

PORT_HTTP = 8420
PORT_WS = 8421
LOG = logging.getLogger("alfredo-bridge")

AGENT_PROMPT_PATH = os.path.expanduser("~/alfredo-kiosk/agent-prompt.txt")
APNS_CONFIG_PATH = os.path.expanduser("~/alfredo-kiosk/apns-config.json")
DEVICE_TOKEN_PATH = os.path.expanduser("~/alfredo-kiosk/device-token.txt")


# =============================================================================
# HTTP Server (health check + one-shot fallback)
# =============================================================================

class HTTPHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/health":
            self._json(200, {"status": "ok", "ws_port": PORT_WS})
        else:
            self._json(404, {"error": "not found"})

    def do_POST(self):
        if self.path == "/register-push":
            self._handle_register_push()
            return
        if self.path != "/chat":
            self._json(404, {"error": "not found"})
            return
        try:
            length = int(self.headers.get("Content-Length", 0))
            body = json.loads(self.rfile.read(length)) if length else {}
            prompt = body.get("prompt", "").strip()
            mode = body.get("mode", "raw")
            if not prompt:
                self._json(400, {"error": "empty prompt"})
                return

            claude_cmd = ["claude"]
            if mode == "agent" and os.path.exists(AGENT_PROMPT_PATH):
                claude_cmd.extend(["--system-prompt", AGENT_PROMPT_PATH])
                LOG.info("HTTP chat using agent prompt from %s", AGENT_PROMPT_PATH)
            elif mode == "agent":
                LOG.warning("HTTP chat requested agent mode but %s not found", AGENT_PROMPT_PATH)
            claude_cmd.extend(["--print", prompt])

            result = subprocess.run(
                claude_cmd,
                capture_output=True, text=True, timeout=110, cwd=os.path.expanduser("~"),
            )
            response_text = result.stdout.strip() or result.stderr.strip() or "(no output)"
            self._json(200, {"response": response_text})
        except subprocess.TimeoutExpired:
            self._json(504, {"error": "claude timed out"})
        except FileNotFoundError:
            self._json(503, {"error": "claude cli not found"})
        except Exception as e:
            self._json(500, {"error": str(e)})

    def _handle_register_push(self):
        try:
            length = int(self.headers.get("Content-Length", 0))
            body = json.loads(self.rfile.read(length)) if length else {}
            token = body.get("device_token", "").strip()
            if not token:
                self._json(400, {"error": "missing device_token"})
                return
            # Persist the token
            with open(DEVICE_TOKEN_PATH, "w") as f:
                f.write(token)
            LOG.info("Registered APNs device token: %s...%s", token[:8], token[-4:])
            self._json(200, {"status": "registered", "token_prefix": token[:8]})
        except Exception as e:
            self._json(500, {"error": str(e)})

    def _json(self, code, data):
        body = json.dumps(data).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        LOG.info(fmt, *args)


def run_http():
    server = HTTPServer(("0.0.0.0", PORT_HTTP), HTTPHandler)
    LOG.info("HTTP listening on :%d", PORT_HTTP)
    server.serve_forever()


# =============================================================================
# WebSocket + PTY Session
# =============================================================================

async def ws_handler(websocket):
    """Handle one WebSocket connection = one interactive claude session."""
    LOG.info("WS client connected from %s", websocket.remote_address)

    master_fd = None
    proc = None

    try:
        # Wait for optional init message with config (model, etc.)
        # Client should send {"type":"init","model":"haiku"} before any input.
        # If first message isn't init, treat it as input after claude starts.
        model = os.environ.get("CLAUDE_MODEL", "haiku")
        mode = "raw"
        first_input = None
        try:
            raw = await asyncio.wait_for(websocket.recv(), timeout=2.0)
            msg = json.loads(raw)
            if msg.get("type") == "init":
                model = msg.get("model", model)
                mode = msg.get("mode", "raw")
                LOG.info("Client requested model=%s mode=%s", model, mode)
            else:
                # Not an init message -- save as first input
                first_input = raw
        except (asyncio.TimeoutError, json.JSONDecodeError):
            pass

        # Create PTY
        master_fd, slave_fd = pty.openpty()

        # Set terminal size (80x24 default)
        winsize = struct.pack("HHHH", 24, 80, 0, 0)
        fcntl.ioctl(slave_fd, termios.TIOCSWINSZ, winsize)

        # Spawn claude in the PTY
        env = os.environ.copy()
        env["TERM"] = "xterm-256color"
        env["COLUMNS"] = "80"
        env["LINES"] = "24"

        claude_cmd = ["claude", "--model", model]

        # Agent mode: prepend the Codex system prompt
        if mode == "agent" and os.path.exists(AGENT_PROMPT_PATH):
            claude_cmd.extend(["--system-prompt", AGENT_PROMPT_PATH])
            LOG.info("Agent mode: loading system prompt from %s", AGENT_PROMPT_PATH)
        elif mode == "agent":
            LOG.warning("Agent mode requested but %s not found, running raw", AGENT_PROMPT_PATH)

        LOG.info("Starting claude with model=%s mode=%s", model, mode)

        proc = subprocess.Popen(
            claude_cmd,
            stdin=slave_fd,
            stdout=slave_fd,
            stderr=slave_fd,
            cwd=os.path.expanduser("~"),
            env=env,
            preexec_fn=os.setsid,
        )
        os.close(slave_fd)

        await websocket.send(json.dumps({
            "type": "status", "data": "started",
            "pid": proc.pid,
        }))

        LOG.info("claude started (pid=%d)", proc.pid)

        # Make master_fd non-blocking
        flags = fcntl.fcntl(master_fd, fcntl.F_GETFL)
        fcntl.fcntl(master_fd, fcntl.F_SETFL, flags | os.O_NONBLOCK)

        # Read from PTY and forward to WebSocket
        async def pty_reader():
            loop = asyncio.get_event_loop()
            while True:
                try:
                    data = await loop.run_in_executor(
                        None, lambda: read_pty(master_fd)
                    )
                    if data is None:
                        break
                    if data:
                        await websocket.send(json.dumps({
                            "type": "output",
                            "data": data,
                        }))
                except Exception:
                    break

            # Process exited
            exit_code = proc.poll()
            await websocket.send(json.dumps({
                "type": "status",
                "data": "exited",
                "exit_code": exit_code,
            }))

        # Read from WebSocket and forward to PTY
        async def ws_reader():
            async for message in websocket:
                try:
                    msg = json.loads(message)
                    if msg.get("type") == "input":
                        text = msg["data"]
                        os.write(master_fd, text.encode())
                    elif msg.get("type") == "resize":
                        cols = msg.get("cols", 80)
                        rows = msg.get("rows", 24)
                        winsize = struct.pack("HHHH", rows, cols, 0, 0)
                        fcntl.ioctl(master_fd, termios.TIOCSWINSZ, winsize)
                        # Signal the process group
                        os.killpg(os.getpgid(proc.pid), signal.SIGWINCH)
                except (json.JSONDecodeError, KeyError, OSError) as e:
                    LOG.warning("ws_reader error: %s", e)

        # If we received a non-init message before starting, replay it
        if first_input is not None:
            try:
                msg = json.loads(first_input)
                if msg.get("type") == "input":
                    os.write(master_fd, msg["data"].encode())
            except (json.JSONDecodeError, KeyError, OSError):
                pass

        # Run both concurrently
        reader_task = asyncio.create_task(pty_reader())
        writer_task = asyncio.create_task(ws_reader())

        done, pending = await asyncio.wait(
            [reader_task, writer_task],
            return_when=asyncio.FIRST_COMPLETED,
        )
        for task in pending:
            task.cancel()

    except Exception as e:
        LOG.exception("ws_handler error")
        try:
            await websocket.send(json.dumps({
                "type": "error", "data": str(e),
            }))
        except Exception:
            pass
    finally:
        # Cleanup
        if proc and proc.poll() is None:
            try:
                os.killpg(os.getpgid(proc.pid), signal.SIGTERM)
                proc.wait(timeout=3)
            except Exception:
                try:
                    os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
                except Exception:
                    pass
        if master_fd is not None:
            try:
                os.close(master_fd)
            except OSError:
                pass
        LOG.info("WS client disconnected")


def read_pty(fd):
    """Read available data from PTY. Returns None if PTY closed."""
    import select
    ready, _, _ = select.select([fd], [], [], 0.1)
    if ready:
        try:
            data = os.read(fd, 4096)
            if not data:
                return None
            return data.decode("utf-8", errors="replace")
        except OSError:
            return None
    return ""


async def run_ws():
    LOG.info("WebSocket listening on :%d", PORT_WS)
    async with serve(ws_handler, "0.0.0.0", PORT_WS):
        await asyncio.Future()  # run forever


# =============================================================================
# Main
# =============================================================================

if __name__ == "__main__":
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(name)s] %(message)s",
    )

    # Run HTTP in a thread
    http_thread = Thread(target=run_http, daemon=True)
    http_thread.start()

    # Run WebSocket in asyncio event loop
    try:
        asyncio.run(run_ws())
    except KeyboardInterrupt:
        LOG.info("shutting down")
