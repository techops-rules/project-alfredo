import http.server, socketserver, os, subprocess, urllib.request, json, time

os.chdir(os.path.dirname(os.path.abspath(__file__)))

# Presence: track last seen time per device
PRESENCE_HOSTS = []  # loaded from presence.json if exists
try:
    with open("presence.json") as f:
        PRESENCE_HOSTS = json.load(f).get("hosts", [])
except:
    pass

last_presence = {"seen": 0, "present": False}

def check_presence():
    if not PRESENCE_HOSTS:
        return {"present": None, "absent_mins": 0, "note": "no hosts configured"}
    now = time.time()
    for host in PRESENCE_HOSTS:
        r = subprocess.run(["ping", "-c", "1", "-W", "1", host],
            capture_output=True, timeout=3)
        if r.returncode == 0:
            last_presence["seen"] = now
            last_presence["present"] = True
            return {"present": True, "absent_mins": 0, "host": host}
    absent_mins = (now - last_presence["seen"]) / 60 if last_presence["seen"] else 999
    last_presence["present"] = False
    return {"present": False, "absent_mins": round(absent_mins, 1)}

class Handler(http.server.SimpleHTTPRequestHandler):
    def do_POST(self):
        if self.path == "/exit-kiosk":
            self.send_response(200); self.end_headers(); self.wfile.write(b"ok")
            subprocess.Popen(["pkill", "-f", "chromium"])
        elif self.path == "/reload-kiosk":
            self.send_response(200); self.end_headers(); self.wfile.write(b"ok")
            subprocess.Popen(["bash", "-c",
                "WAYLAND_DISPLAY=wayland-0 XDG_RUNTIME_DIR=/run/user/1000 "
                "chromium --ozone-platform=wayland http://localhost:8430/ 2>/dev/null"])
        elif self.path == "/proxy/display":
            length = int(self.headers.get("Content-Length", 0))
            body = json.loads(self.rfile.read(length)) if length else {}
            on = body.get("on", True)
            cmd = "wlr-randr --output HDMI-A-1 --" + ("on" if on else "off")
            subprocess.Popen(["bash", "-c",
                f"WAYLAND_DISPLAY=wayland-0 XDG_RUNTIME_DIR=/run/user/1000 {cmd}"])
            self.send_response(200); self.end_headers()
            self.wfile.write(json.dumps({"ok": True, "on": on}).encode())
        elif self.path == "/proxy/presence-hosts":
            length = int(self.headers.get("Content-Length", 0))
            body = json.loads(self.rfile.read(length)) if length else {}
            hosts = body.get("hosts", [])
            with open("presence.json", "w") as f:
                json.dump({"hosts": hosts}, f)
            global PRESENCE_HOSTS
            PRESENCE_HOSTS = hosts
            self.send_response(200); self.end_headers()
            self.wfile.write(json.dumps({"ok": True}).encode())
        else:
            self.send_response(404); self.end_headers()

    def do_GET(self):
        if self.path == "/proxy/health":
            self._proxy_json("http://localhost:8420/health")
        elif self.path == "/proxy/icloud":
            try:
                urllib.request.urlopen("https://www.icloud.com", timeout=3)
                self._json({"ok": True})
            except:
                self._json({"ok": False})
        elif self.path == "/proxy/tailscale":
            try:
                r = subprocess.run(["tailscale", "status", "--json"],
                    capture_output=True, text=True, timeout=3)
                data = json.loads(r.stdout)
                ok = data.get("BackendState") == "Running"
                self._json({"ok": ok, "state": data.get("BackendState")})
            except:
                self._json({"ok": False})
        elif self.path == "/proxy/presence":
            self._json(check_presence())
        elif self.path == "/proxy/presence-hosts":
            self._json({"hosts": PRESENCE_HOSTS})
        else:
            super().do_GET()

    def _proxy_json(self, url):
        try:
            with urllib.request.urlopen(url, timeout=3) as r:
                data = r.read()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers(); self.wfile.write(data)
        except:
            self._json({"status": "offline"})

    def _json(self, obj):
        data = json.dumps(obj).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers(); self.wfile.write(data)

    def log_message(self, *a): pass

socketserver.TCPServer.allow_reuse_address = True
socketserver.TCPServer(("", 8430), Handler).serve_forever()
