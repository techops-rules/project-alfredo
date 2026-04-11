import http.server, socketserver, os, subprocess, urllib.request, json, time, secrets
from datetime import datetime, timezone, timedelta
import re, threading

os.chdir(os.path.dirname(os.path.abspath(__file__)))

# Bearer token for system control endpoints — generated on startup, logged for admin
AUTH_TOKEN = os.environ.get("ALFREDO_KIOSK_TOKEN", secrets.token_hex(16))

# Presence: track last seen time per device
PRESENCE_HOSTS = []  # loaded from presence.json if exists
try:
    with open("presence.json") as f:
        PRESENCE_HOSTS = json.load(f).get("hosts", [])
except Exception:
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

# ── Calendar ─────────────────────────────────────────────────
# iCal feeds fetched by Pi directly (works without Mac)
# Mac can also push richer EventKit data via POST /proxy/calendar

ICAL_FEEDS_FILE = "calendar-feeds.json"
CALENDAR_CACHE_FILE = "calendar-cache.json"
CALENDAR_FETCH_INTERVAL = 300  # 5 minutes

# Calendar state
cal_state = {
    "ical_events": [],       # from iCal feeds
    "mac_events": [],        # from Mac push
    "mac_push_time": 0,      # epoch when Mac last pushed
    "ical_fetch_time": 0,    # epoch when iCal last fetched
}

def load_ical_feeds():
    """Load configured iCal feed URLs."""
    try:
        with open(ICAL_FEEDS_FILE) as f:
            return json.load(f).get("feeds", [])
    except Exception:
        return []

def save_ical_feeds(feeds):
    with open(ICAL_FEEDS_FILE, "w") as f:
        json.dump({"feeds": feeds}, f, indent=2)

def parse_ical(ics_text):
    """Minimal iCal parser — extracts VEVENT blocks into dicts.
    No external dependencies needed."""
    events = []
    # Use Pi local time so "today" matches the user's timezone
    now_local = datetime.now()
    today_start = now_local.replace(hour=0, minute=0, second=0, microsecond=0) - timedelta(hours=1)
    tomorrow_end = today_start + timedelta(days=3)

    # Unfold long lines (RFC 5545 §3.1)
    ics_text = re.sub(r'\r?\n[ \t]', '', ics_text)

    for block in re.split(r'BEGIN:VEVENT', ics_text)[1:]:
        end_idx = block.find('END:VEVENT')
        if end_idx < 0:
            continue
        block = block[:end_idx]

        def prop(name):
            # Match property with optional params: DTSTART;TZID=...:20260410T090000
            m = re.search(rf'^{name}[;:](.*)$', block, re.MULTILINE)
            if not m:
                return None
            val = m.group(1)
            # Strip params — value is after last colon if params present
            if ';' in name or ':' in val:
                parts = val.split(':')
                if len(parts) > 1:
                    val = parts[-1]
            return val.strip()

        summary = prop('SUMMARY') or '(no title)'
        location = prop('LOCATION')
        description = prop('DESCRIPTION')

        dtstart_raw = prop('DTSTART')
        dtend_raw = prop('DTEND')

        if not dtstart_raw:
            continue

        start = parse_ical_dt(dtstart_raw)
        end = parse_ical_dt(dtend_raw) if dtend_raw else start

        if not start:
            continue

        # Filter to today + tomorrow only
        if end < today_start or start > tomorrow_end:
            continue

        is_all_day = len(dtstart_raw) == 8  # 20260410 vs 20260410T090000Z

        events.append({
            "title": summary,
            "startTime": start.isoformat(),
            "endTime": end.isoformat(),
            "location": location,
            "isAllDay": is_all_day,
            "source": "ical",
        })

    return events

def parse_ical_dt(raw):
    """Parse iCal datetime to naive local datetime for display.
    UTC events (Z suffix) are converted to Pi local time.
    TZID-qualified events have their timezone stripped but kept as-is
    (close enough when Pi and user are in same timezone)."""
    raw = raw.strip()
    is_utc = raw.endswith('Z')
    raw = raw.rstrip('Z')
    try:
        if 'T' in raw:
            dt = datetime.strptime(raw, '%Y%m%dT%H%M%S')
        else:
            dt = datetime.strptime(raw, '%Y%m%d')
        if is_utc:
            # Convert UTC → Pi local time
            dt = dt.replace(tzinfo=timezone.utc).astimezone().replace(tzinfo=None)
        return dt
    except Exception:
        return None

def fetch_ical_feeds():
    """Fetch all configured iCal feeds and parse events."""
    feeds = load_ical_feeds()
    all_events = []
    for feed in feeds:
        url = feed.get("url", "")
        label = feed.get("label", "calendar")
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "alfredo-kiosk/1.0"})
            with urllib.request.urlopen(req, timeout=10) as r:
                ics = r.read().decode("utf-8", errors="replace")
            events = parse_ical(ics)
            for e in events:
                e["calendar"] = label
            all_events.extend(events)
        except Exception as ex:
            print(f"[cal] Failed to fetch {label}: {ex}")
    cal_state["ical_events"] = all_events
    cal_state["ical_fetch_time"] = time.time()
    # Persist to disk for fast startup
    try:
        with open(CALENDAR_CACHE_FILE, "w") as f:
            json.dump({"ical": all_events, "ts": time.time()}, f)
    except Exception:
        pass

def calendar_fetch_loop():
    """Background thread: fetch iCal feeds every 5 min."""
    while True:
        try:
            fetch_ical_feeds()
        except Exception as ex:
            print(f"[cal] fetch error: {ex}")
        time.sleep(CALENDAR_FETCH_INTERVAL)

def get_merged_calendar():
    """Return merged calendar: prefer Mac push if fresh (<10min), else iCal."""
    now = time.time()
    mac_fresh = (now - cal_state["mac_push_time"]) < 600  # 10 min
    events = []
    seen_keys = set()

    # Mac events preferred when fresh (richer data: attendees, notes, organizer)
    if mac_fresh and cal_state["mac_events"]:
        for e in cal_state["mac_events"]:
            key = (e.get("title", ""), e.get("startTime", ""))
            seen_keys.add(key)
            events.append({**e, "source": "mac"})

    # Add iCal events not already covered by Mac push
    for e in cal_state["ical_events"]:
        key = (e.get("title", ""), e.get("startTime", ""))
        if key not in seen_keys:
            events.append(e)

    # Sort by start time
    events.sort(key=lambda e: e.get("startTime", ""))
    return {
        "events": events,
        "source": "hybrid",
        "mac_fresh": mac_fresh,
        "ical_fetch_age": round(now - cal_state["ical_fetch_time"]) if cal_state["ical_fetch_time"] else None,
        "mac_push_age": round(now - cal_state["mac_push_time"]) if cal_state["mac_push_time"] else None,
    }

# Load cached events from disk on startup
try:
    with open(CALENDAR_CACHE_FILE) as f:
        cached = json.load(f)
        cal_state["ical_events"] = cached.get("ical", [])
        cal_state["ical_fetch_time"] = cached.get("ts", 0)
except Exception:
    pass

# Start background fetch thread
threading.Thread(target=calendar_fetch_loop, daemon=True).start()

MAX_BODY = 1024 * 1024  # 1MB max request body

class Handler(http.server.SimpleHTTPRequestHandler):
    def _read_json_body(self):
        length = int(self.headers.get("Content-Length", 0))
        if length > MAX_BODY:
            self.send_response(413); self.end_headers()
            return None
        return json.loads(self.rfile.read(length)) if length else {}

    def _check_auth(self):
        """Check bearer token for system control endpoints."""
        auth = self.headers.get("Authorization", "")
        if auth != f"Bearer {AUTH_TOKEN}":
            # Also allow requests from localhost without token
            client_ip = self.client_address[0]
            if client_ip not in ("127.0.0.1", "::1"):
                self._json({"error": "unauthorized"}, code=403)
                return False
        return True

    def do_POST(self):
        if self.path == "/exit-kiosk":
            if not self._check_auth(): return
            self.send_response(200); self.end_headers(); self.wfile.write(b"ok")
            subprocess.Popen(["pkill", "-f", "chromium"])
        elif self.path == "/proxy/reboot":
            if not self._check_auth(): return
            self.send_response(200); self.end_headers(); self.wfile.write(b"ok")
            subprocess.Popen(["sudo", "reboot"])
        elif self.path == "/reload-kiosk":
            if not self._check_auth(): return
            self.send_response(200); self.end_headers(); self.wfile.write(b"ok")
            env = {**os.environ, "WAYLAND_DISPLAY": "wayland-0", "XDG_RUNTIME_DIR": "/run/user/1000"}
            subprocess.Popen(
                ["chromium", "--ozone-platform=wayland", "http://localhost:8430/"],
                env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
            )
        elif self.path == "/proxy/display":
            if not self._check_auth(): return
            body = self._read_json_body()
            if body is None: return
            on = body.get("on", True)
            flag = "--on" if on else "--off"
            env = {**os.environ, "WAYLAND_DISPLAY": "wayland-0", "XDG_RUNTIME_DIR": "/run/user/1000"}
            subprocess.Popen(
                ["wlr-randr", "--output", "HDMI-A-1", flag],
                env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
            )
            self.send_response(200); self.end_headers()
            self.wfile.write(json.dumps({"ok": True, "on": on}).encode())
        elif self.path == "/proxy/presence-hosts":
            body = self._read_json_body()
            if body is None: return
            hosts = body.get("hosts", [])
            with open("presence.json", "w") as f:
                json.dump({"hosts": hosts}, f)
            global PRESENCE_HOSTS
            PRESENCE_HOSTS = hosts
            self.send_response(200); self.end_headers()
            self.wfile.write(json.dumps({"ok": True}).encode())
        elif self.path == "/proxy/calendar":
            # Mac pushes richer EventKit events here
            body = self._read_json_body()
            if body is None: return
            cal_state["mac_events"] = body.get("events", [])
            cal_state["mac_push_time"] = time.time()
            self._json({"ok": True, "count": len(cal_state["mac_events"])})
        elif self.path == "/proxy/calendar-feeds":
            # Configure iCal feed URLs
            body = self._read_json_body()
            if body is None: return
            feeds = body.get("feeds", [])
            save_ical_feeds(feeds)
            # Trigger immediate fetch
            threading.Thread(target=fetch_ical_feeds, daemon=True).start()
            self._json({"ok": True, "feeds": len(feeds)})
        else:
            self.send_response(404); self.end_headers()

    def _suggest_tasks(self):
        """Call Claude bridge to generate today's work task list from calendar context."""
        try:
            cal = get_merged_calendar()
            now = datetime.now(timezone.utc)
            today_str = now.strftime("%A, %B %-d, %Y")
            events_summary = []
            for e in cal.get("events", []):
                title = e.get("title", "")
                start = e.get("startTime", "")
                if start:
                    try:
                        dt = datetime.fromisoformat(start.replace("Z", "+00:00"))
                        time_str = dt.strftime("%-I:%M %p")
                    except Exception:
                        time_str = start
                    events_summary.append(f"- {time_str}: {title}")
                else:
                    events_summary.append(f"- (all day): {title}")
            cal_text = "\n".join(events_summary) if events_summary else "(no events today)"

            prompt = (
                f"Today is {today_str}. Here are my calendar events:\n{cal_text}\n\n"
                "Based on this context, suggest a focused work task list for today. "
                "Return ONLY a JSON array of objects with 'text' (string) and 'done' (false). "
                "5-8 tasks max. Tasks should be specific, actionable, and realistic. "
                "No explanation, no markdown, just the JSON array."
            )
            req_data = json.dumps({"prompt": prompt}).encode()
            req = urllib.request.Request(
                "http://localhost:8420/chat",
                data=req_data,
                headers={"Content-Type": "application/json"},
                method="POST"
            )
            with urllib.request.urlopen(req, timeout=20) as r:
                result = json.loads(r.read())
            response_text = result.get("response", "")
            # Extract JSON array from response
            match = re.search(r'\[.*\]', response_text, re.DOTALL)
            if match:
                tasks = json.loads(match.group(0))
                # Validate structure
                tasks = [{"text": str(t.get("text", "")), "done": bool(t.get("done", False))}
                         for t in tasks if t.get("text")]
                return {"ok": True, "tasks": tasks, "source": "claude"}
        except Exception as ex:
            print(f"[suggest-tasks] error: {ex}")
        return {"ok": False, "tasks": [], "source": "error"}

    def do_GET(self):
        if self.path == "/proxy/health":
            self._proxy_json("http://localhost:8420/health")
        elif self.path == "/proxy/icloud":
            try:
                urllib.request.urlopen("https://www.icloud.com", timeout=3)
                self._json({"ok": True})
            except Exception:
                self._json({"ok": False})
        elif self.path == "/proxy/tailscale":
            try:
                r = subprocess.run(["tailscale", "status", "--json"],
                    capture_output=True, text=True, timeout=3)
                data = json.loads(r.stdout)
                ok = data.get("BackendState") == "Running"
                self._json({"ok": ok, "state": data.get("BackendState")})
            except Exception:
                self._json({"ok": False})
        elif self.path == "/proxy/presence":
            self._json(check_presence())
        elif self.path == "/proxy/presence-hosts":
            self._json({"hosts": PRESENCE_HOSTS})
        elif self.path == "/proxy/calendar":
            self._json(get_merged_calendar())
        elif self.path == "/proxy/calendar-feeds":
            self._json({"feeds": load_ical_feeds()})
        elif self.path == "/proxy/suggest-tasks":
            self._json(self._suggest_tasks())
        else:
            super().do_GET()

    def _proxy_json(self, url):
        try:
            with urllib.request.urlopen(url, timeout=3) as r:
                data = r.read()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers(); self.wfile.write(data)
        except Exception:
            self._json({"status": "offline"})

    def _json(self, obj, code=200):
        data = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.end_headers(); self.wfile.write(data)

    def log_message(self, *a): pass

socketserver.TCPServer.allow_reuse_address = True
socketserver.TCPServer(("", 8430), Handler).serve_forever()
