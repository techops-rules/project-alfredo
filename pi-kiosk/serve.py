import http.server, socketserver, os, subprocess, urllib.request, json, time, secrets
from datetime import datetime, timezone, timedelta
import re, threading
from pathlib import Path
from uuid import uuid4

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

# Voice event queue — wake listener POSTs events, kiosk polls them
voice_events = []  # list of {type, text, reply, timestamp}
VOICE_EVENT_MAX = 20

# Mute state — when True, wake listener should not process voice
voice_muted = False

# Push-to-talk activation — set True from kiosk/phone, cleared by wake listener
voice_push_active = False

# Kiosk-side context snapshot for Direct Mode
direct_context = {
    "workTasks": [],
    "lifeTasks": [],
    "waitingItems": [],
    "deferredItems": [],
    "projects": [],
    "scratch": [],
    "calendar": [],
    "updatedAt": 0,
}

OPENAI_API_KEY = os.environ.get("OPENAI_API_KEY", "")
REALTIME_MODEL = os.environ.get("ALFREDO_REALTIME_MODEL", "gpt-realtime")
REALTIME_VOICE = os.environ.get("ALFREDO_REALTIME_VOICE", "marin")
REALTIME_IDLE_TIMEOUT = int(os.environ.get("ALFREDO_REALTIME_IDLE_TIMEOUT", "300"))
HUE_CONTROL_URL = os.environ.get("ALFREDO_HUE_CONTROL_URL", "")
GOVEE_CONTROL_URL = os.environ.get("ALFREDO_GOVEE_CONTROL_URL", "")
PERSONA_PATH = Path(os.path.expanduser("~/alfredo-kiosk/persona.md"))
MEMORY_PATHS = [
    Path(os.path.expanduser("~/alfredo-kiosk/memory.md")),
    Path(os.path.expanduser("~/.claude/projects/-Users-todd-Projects-project-alfredo/memory/MEMORY.md")),
]

REALTIME_TOOL_SCHEMAS = [
    {
        "type": "function",
        "name": "get_today_summary",
        "description": "Get Alfredo's today summary using calendar, open tasks, waiting items, and kiosk context.",
        "parameters": {"type": "object", "properties": {}},
    },
    {
        "type": "function",
        "name": "get_tomorrow_summary",
        "description": "Get tomorrow's schedule and likely workload summary.",
        "parameters": {"type": "object", "properties": {}},
    },
    {
        "type": "function",
        "name": "get_open_tasks",
        "description": "List current open work and personal tasks with waiting/deferred context.",
        "parameters": {"type": "object", "properties": {}},
    },
    {
        "type": "function",
        "name": "get_active_projects",
        "description": "Return active project context when available.",
        "parameters": {"type": "object", "properties": {}},
    },
    {
        "type": "function",
        "name": "get_recent_memory",
        "description": "Return recent Alfredo memory notes when available.",
        "parameters": {"type": "object", "properties": {}},
    },
    {
        "type": "function",
        "name": "get_response_candidates",
        "description": "Answer who Alfredo needs to respond to based on waiting items, followups, and nearby meetings.",
        "parameters": {"type": "object", "properties": {}},
    },
    {
        "type": "function",
        "name": "create_task",
        "description": "Create a new Alfredo task.",
        "parameters": {
            "type": "object",
            "properties": {
                "text": {"type": "string"},
                "scope": {"type": "string", "enum": ["work", "personal"]},
                "urgency": {"type": "string", "enum": ["normal", "high"]},
            },
            "required": ["text"],
        },
    },
    {
        "type": "function",
        "name": "create_followup",
        "description": "Create a follow-up or waiting-on item.",
        "parameters": {
            "type": "object",
            "properties": {
                "text": {"type": "string"},
                "person": {"type": "string"},
                "when": {"type": "string"},
            },
            "required": ["text"],
        },
    },
    {
        "type": "function",
        "name": "create_reminder",
        "description": "Create a reminder or callback task with fuzzy timing like later or tomorrow morning.",
        "parameters": {
            "type": "object",
            "properties": {
                "text": {"type": "string"},
                "when": {"type": "string"},
                "scope": {"type": "string", "enum": ["work", "personal"]},
            },
            "required": ["text"],
        },
    },
    {
        "type": "function",
        "name": "control_smart_lights",
        "description": "Control configured Hue or Govee lights through Alfredo's local automation bridge.",
        "parameters": {
            "type": "object",
            "properties": {
                "provider": {"type": "string", "enum": ["hue", "govee"]},
                "target": {"type": "string"},
                "power": {"type": "string", "enum": ["on", "off"]},
                "brightness": {"type": "integer", "minimum": 1, "maximum": 100},
                "scene": {"type": "string"},
                "color": {"type": "string"},
            },
            "required": ["provider"],
        },
    },
]


def load_persona():
    try:
        return PERSONA_PATH.read_text(encoding="utf-8").strip()
    except Exception:
        return ""


def load_recent_memory():
    for path in MEMORY_PATHS:
        try:
            content = path.read_text(encoding="utf-8")
        except Exception:
            continue
        bullets = [line.strip() for line in content.splitlines() if line.strip().startswith("- ")]
        if bullets:
            return bullets[:6]
    return []


def current_context(snapshot=None):
    state = dict(direct_context)
    if snapshot:
        state.update({
            "workTasks": snapshot.get("workTasks", state["workTasks"]),
            "lifeTasks": snapshot.get("lifeTasks", state["lifeTasks"]),
            "waitingItems": snapshot.get("waitingItems", state.get("waitingItems", [])),
            "deferredItems": snapshot.get("deferredItems", state.get("deferredItems", [])),
            "projects": snapshot.get("projects", state.get("projects", [])),
            "scratch": snapshot.get("scratch", state["scratch"]),
            "calendar": snapshot.get("calendar", state["calendar"]),
        })
    if not state.get("calendar"):
        state["calendar"] = get_merged_calendar().get("events", [])
    return state


def format_event_summary(event):
    title = event.get("title", "(untitled)")
    start = event.get("startTime", "")
    location = event.get("location")
    try:
        dt = datetime.fromisoformat(start.replace("Z", "+00:00"))
        if dt.tzinfo is not None:
            dt = dt.astimezone()
        time_str = dt.strftime("%-I:%M %p").lower()
    except Exception:
        time_str = start or "time tbd"
    suffix = f" @ {location}" if location else ""
    return f"{time_str} {title}{suffix}"


def summarize_events_for_day(events, day_offset=0):
    target = datetime.now().astimezone().date() + timedelta(days=day_offset)
    filtered = []
    for event in events or []:
        start = event.get("startTime", "")
        try:
            dt = datetime.fromisoformat(start.replace("Z", "+00:00"))
            if dt.tzinfo is not None:
                dt = dt.astimezone()
            if dt.date() == target:
                filtered.append((dt, event))
        except Exception:
            continue
    filtered.sort(key=lambda item: item[0])
    return [format_event_summary(event) for _, event in filtered[:8]]


def open_task_lines(tasks):
    items = []
    for task in tasks or []:
        if task.get("done") or task.get("status") in ("waiting", "deferred"):
            continue
        text = task.get("text", "").strip()
        if text:
            items.append(text)
    return items


def summarize_open_tasks(state):
    work = open_task_lines(state.get("workTasks", []))
    life = open_task_lines(state.get("lifeTasks", []))
    waiting = [item.get("text", "") for item in state.get("waitingItems", []) if item.get("text")]
    deferred = [item.get("text", "") for item in state.get("deferredItems", []) if item.get("text")]
    return {
        "work": work[:6],
        "personal": life[:4],
        "waiting": waiting[:4],
        "deferred": deferred[:4],
    }


def summarize_projects(state):
    projects = state.get("projects") or []
    if not projects:
        return []
    lines = []
    for project in projects[:6]:
        name = project.get("name", "project")
        status = project.get("status", "")
        percent = project.get("percent")
        detail = " // ".join(part for part in [
            status,
            f"{percent}%" if percent is not None else ""
        ] if part)
        lines.append(f"{name}{(' // ' + detail) if detail else ''}")
    return lines


def infer_scope(args):
    scope = (args.get("scope") or "").strip().lower()
    if scope in ("work", "personal"):
        return scope
    text = (args.get("text") or "").lower()
    personal_terms = ("home", "family", "mom", "dad", "wife", "kids", "doctor", "dentist")
    return "personal" if any(term in text for term in personal_terms) else "work"


def resolve_fuzzy_time(label):
    raw = (label or "later").strip().lower()
    now = datetime.now().astimezone()
    if not raw or raw == "later":
        if now.hour < 17:
            target = now.replace(hour=max(now.hour + 1, 15), minute=30, second=0, microsecond=0)
            return {"label": target.strftime("today at %-I:%M %p").lower(), "bucket": "today"}
        target = (now + timedelta(days=1)).replace(hour=9, minute=0, second=0, microsecond=0)
        return {"label": target.strftime("tomorrow at %-I:%M %p").lower(), "bucket": "tomorrow"}
    if raw in ("tomorrow", "tomorrow morning"):
        target = (now + timedelta(days=1)).replace(hour=9, minute=0, second=0, microsecond=0)
        return {"label": target.strftime("tomorrow at %-I:%M %p").lower(), "bucket": "tomorrow"}
    if raw in ("this afternoon", "afternoon"):
        target = now.replace(hour=15, minute=30, second=0, microsecond=0)
        return {"label": target.strftime("today at %-I:%M %p").lower(), "bucket": "today"}
    return {"label": raw, "bucket": "custom"}


def build_reminder_text(text, when_info):
    normalized = text.strip()
    if when_info["label"] and when_info["label"] not in normalized.lower():
        return f"{normalized} ({when_info['label']})"
    return normalized


def response_candidates(state):
    candidates = []
    for item in state.get("waitingItems", [])[:6]:
        text = item.get("text", "").strip()
        if text:
            reason = item.get("person") or "waiting item"
            candidates.append({"text": text, "reason": reason})
    for task in state.get("workTasks", []) + state.get("lifeTasks", []):
        text = task.get("text", "").strip()
        if text and re.search(r"\b(reply|respond|email|call back|follow up)\b", text, re.I):
            candidates.append({"text": text, "reason": "action keyword"})
    upcoming = summarize_events_for_day(state.get("calendar", []), 0)[:2]
    for event in upcoming:
        candidates.append({"text": event, "reason": "upcoming meeting"})
    deduped = []
    seen = set()
    for item in candidates:
        key = item["text"].lower()
        if key in seen:
            continue
        seen.add(key)
        deduped.append(item)
    return deduped[:6]


def build_realtime_instructions():
    persona = load_persona()
    persona_block = f"\n\nPersona:\n{persona}\n" if persona else ""
    return (
        "You are Alfredo in live voice direct mode. "
        "Be concise, warm, and decisive. Prefer tool calls over guessing. "
        "When a task, reminder, or follow-up is created, briefly confirm the saved action in one sentence. "
        "Use the smart light control tool when Todd explicitly asks about Hue or Govee lights and the bridge is configured. "
        "If timing is ambiguous but risky, ask one short follow-up. "
        "Do not pretend to have completed actions unless a tool confirms success."
        + persona_block
    )


def build_realtime_session_payload():
    return {
        "session": {
            "type": "realtime",
            "model": REALTIME_MODEL,
            "instructions": build_realtime_instructions(),
            "output_modalities": ["audio"],
            "tools": REALTIME_TOOL_SCHEMAS,
            "tool_choice": "auto",
            "audio": {
                "input": {
                    "turn_detection": {
                        "type": "server_vad",
                        "threshold": 0.56,
                        "prefix_padding_ms": 360,
                        "silence_duration_ms": 520,
                        "create_response": True,
                        "interrupt_response": True,
                    }
                },
                "output": {"voice": REALTIME_VOICE},
            },
        }
    }


def dispatch_realtime_tool(tool_name, args, snapshot=None):
    state = current_context(snapshot)
    memory = load_recent_memory()

    if tool_name == "get_today_summary":
        return {"ok": True, "summary": {
            "events": summarize_events_for_day(state.get("calendar", []), 0),
            "tasks": summarize_open_tasks(state),
        }}
    if tool_name == "get_tomorrow_summary":
        return {"ok": True, "summary": {
            "events": summarize_events_for_day(state.get("calendar", []), 1),
            "tasks": summarize_open_tasks(state),
        }}
    if tool_name == "get_open_tasks":
        return {"ok": True, "tasks": summarize_open_tasks(state)}
    if tool_name == "get_active_projects":
        return {"ok": True, "projects": summarize_projects(state)}
    if tool_name == "get_recent_memory":
        return {"ok": True, "memory": memory}
    if tool_name == "get_response_candidates":
        return {"ok": True, "candidates": response_candidates(state)}
    if tool_name == "create_task":
        text = (args.get("text") or "").strip()
        if not text:
            return {"ok": False, "error": "missing task text"}
        scope = infer_scope(args)
        task = {
            "text": text,
            "done": False,
            "status": "todo",
            "urgency": "high" if args.get("urgency") == "high" else None,
        }
        return {
            "ok": True,
            "assistant_confirmation": f"I added {text}.",
            "client_action": {"kind": "append_task", "list": "workTasks" if scope == "work" else "lifeTasks", "task": task},
            "saved": {"type": "task", "scope": scope, "text": text},
        }
    if tool_name == "create_followup":
        text = (args.get("text") or "").strip()
        if not text:
            return {"ok": False, "error": "missing followup text"}
        person = (args.get("person") or "").strip()
        item = {"text": text}
        if person:
            item["person"] = person
        return {
            "ok": True,
            "assistant_confirmation": f"I added that follow-up.",
            "client_action": {"kind": "append_waiting", "item": item},
            "saved": {"type": "followup", "text": text, "person": person},
        }
    if tool_name == "create_reminder":
        text = (args.get("text") or "").strip()
        if not text:
            return {"ok": False, "error": "missing reminder text"}
        when_info = resolve_fuzzy_time(args.get("when"))
        scope = infer_scope(args)
        saved_text = build_reminder_text(text, when_info)
        task = {
            "text": saved_text,
            "done": False,
            "status": "todo",
            "reminderWhen": when_info["label"],
        }
        return {
            "ok": True,
            "assistant_confirmation": f"I added that reminder for {when_info['label']}.",
            "client_action": {"kind": "append_task", "list": "workTasks" if scope == "work" else "lifeTasks", "task": task},
            "saved": {"type": "reminder", "text": text, "when": when_info["label"], "scope": scope},
        }
    if tool_name == "control_smart_lights":
        provider = (args.get("provider") or "").strip().lower()
        target = (args.get("target") or "default").strip()
        endpoint = HUE_CONTROL_URL if provider == "hue" else GOVEE_CONTROL_URL if provider == "govee" else ""
        if not provider:
            return {"ok": False, "error": "missing light provider"}
        if not endpoint:
            return {"ok": False, "error": f"{provider} lights are not configured on this kiosk yet"}
        payload = {
            "provider": provider,
            "target": target,
            "power": args.get("power"),
            "brightness": args.get("brightness"),
            "scene": args.get("scene"),
            "color": args.get("color"),
        }
        try:
            req = urllib.request.Request(
                endpoint,
                data=json.dumps(payload).encode(),
                headers={"Content-Type": "application/json"},
                method="POST",
            )
            with urllib.request.urlopen(req, timeout=10) as response:
                body = response.read().decode().strip()
                data = json.loads(body) if body else {}
            summary = data.get("summary") or f"{provider} lights updated"
            return {
                "ok": True,
                "assistant_confirmation": summary,
                "saved": {"type": "light_control", "provider": provider, "target": target, "payload": payload},
                "bridge_result": data,
            }
        except Exception as ex:
            return {"ok": False, "error": f"{provider} bridge failed: {ex}"}
    return {"ok": False, "error": f"unknown tool: {tool_name}"}

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
        elif self.path == "/proxy/voice-mute":
            global voice_muted
            body = self._read_json_body()
            if body is None: return
            voice_muted = body.get("muted", not voice_muted)
            self._json({"muted": voice_muted})
        elif self.path == "/proxy/voice-activate":
            global voice_push_active
            body = self._read_json_body()
            if body is None: return
            voice_push_active = body.get("active", True)
            self._json({"active": voice_push_active})
        elif self.path == "/proxy/realtime/session":
            body = self._read_json_body()
            if body is None: return
            if not OPENAI_API_KEY:
                self._json({"error": "OPENAI_API_KEY is not configured on the kiosk"}, code=503)
                return
            session_id = body.get("sessionId") or str(uuid4())
            payload = build_realtime_session_payload()
            try:
                req = urllib.request.Request(
                    "https://api.openai.com/v1/realtime/client_secrets",
                    data=json.dumps(payload).encode(),
                    headers={
                        "Authorization": f"Bearer {OPENAI_API_KEY}",
                        "Content-Type": "application/json",
                    },
                    method="POST",
                )
                with urllib.request.urlopen(req, timeout=20) as r:
                    data = json.loads(r.read())
                self._json({
                    "client_secret": data.get("client_secret") or data,
                    "session": payload["session"],
                    "meta": {
                        "sessionId": session_id,
                        "surface": body.get("surface", "kiosk"),
                        "conversationMode": body.get("conversationMode", "direct"),
                        "idleTimeout": REALTIME_IDLE_TIMEOUT,
                    },
                })
            except Exception as ex:
                self._json({"error": f"failed to create realtime session: {ex}"}, code=502)
        elif self.path == "/proxy/realtime/tool":
            body = self._read_json_body()
            if body is None: return
            tool_name = body.get("tool", "")
            args = body.get("arguments", {}) or {}
            snapshot = body.get("state_snapshot", {}) or {}
            result = dispatch_realtime_tool(tool_name, args, snapshot=snapshot)
            self._json(result, code=200 if result.get("ok") else 400)
        elif self.path == "/proxy/layout":
            # Editor pushes layout updates — saves to layouts.json, triggers kiosk reload
            body = self._read_json_body()
            if body is None: return
            action = body.get("action", "apply")  # apply, save-mode, get
            if action == "apply":
                # Apply layouts to kiosk — save and trigger reload
                layouts = body.get("layouts", {})
                with open("layouts.json", "w") as f:
                    json.dump({"layouts": layouts, "updated": time.time()}, f, indent=2)
                # Trigger kiosk reload
                env = {**os.environ, "WAYLAND_DISPLAY": "wayland-0", "XDG_RUNTIME_DIR": "/run/user/1000"}
                subprocess.Popen(
                    ["chromium", "--ozone-platform=wayland", "http://localhost:8430/?layout_reload=1"],
                    env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
                )
                self._json({"ok": True, "action": "applied", "modes": list(layouts.keys())})
            elif action == "save-mode":
                # Save a new custom mode with optional schedule
                mode_name = body.get("name", "")
                mode_layout = body.get("layout", {})
                schedule = body.get("schedule", None)  # {time:"22:00", days:["SAT","SUN"], condition:"night"}
                if not mode_name:
                    self._json({"ok": False, "error": "name required"}); return
                try:
                    with open("layouts.json") as f:
                        data = json.load(f)
                except Exception:
                    data = {"layouts": {}, "schedules": {}}
                data.setdefault("layouts", {})[mode_name] = mode_layout
                if schedule:
                    data.setdefault("schedules", {})[mode_name] = schedule
                data["updated"] = time.time()
                with open("layouts.json", "w") as f:
                    json.dump(data, f, indent=2)
                self._json({"ok": True, "action": "saved", "mode": mode_name})
            elif action == "revert":
                # Delete layouts.json to revert to hardcoded defaults
                try:
                    os.remove("layouts.json")
                except FileNotFoundError:
                    pass
                env = {**os.environ, "WAYLAND_DISPLAY": "wayland-0", "XDG_RUNTIME_DIR": "/run/user/1000"}
                subprocess.Popen(
                    ["chromium", "--ozone-platform=wayland", "http://localhost:8430/"],
                    env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
                )
                self._json({"ok": True, "action": "reverted"})
            else:
                self._json({"ok": False, "error": "unknown action"})
        elif self.path == "/proxy/voice-event":
            # Wake listener posts voice events here
            body = self._read_json_body()
            if body is None: return
            event = {
                "type": body.get("type", "wake"),  # wake, command, reply, listening
                "text": body.get("text", ""),
                "reply": body.get("reply", ""),
                "timestamp": time.time(),
                "mode": body.get("mode", "voice"),
                "session_id": body.get("session_id"),
                "surface": body.get("surface", "kiosk"),
                "session_state": body.get("session_state"),
                "origin": body.get("origin", "server"),
            }
            voice_events.append(event)
            if len(voice_events) > VOICE_EVENT_MAX:
                voice_events.pop(0)
            self._json({"ok": True})
        elif self.path == "/proxy/direct-context":
            body = self._read_json_body()
            if body is None: return
            direct_context["workTasks"] = body.get("workTasks", [])
            direct_context["lifeTasks"] = body.get("lifeTasks", [])
            direct_context["waitingItems"] = body.get("waitingItems", [])
            direct_context["deferredItems"] = body.get("deferredItems", [])
            direct_context["projects"] = body.get("projects", [])
            direct_context["scratch"] = body.get("scratch", [])
            direct_context["calendar"] = body.get("calendar", [])
            direct_context["updatedAt"] = time.time()
            self._json({"ok": True, "updatedAt": direct_context["updatedAt"]})
        else:
            self.send_response(404); self.end_headers()

    def _suggest_tasks(self, scope="work"):
        """Call Claude bridge to generate today's task list from all available context.
        scope: 'work' or 'life' — generates different task types."""
        try:
            cal = get_merged_calendar()
            now = datetime.now(timezone.utc)
            local_now = datetime.now()
            today_str = local_now.strftime("%A, %B %-d, %Y")
            hour = local_now.hour
            is_weekend = local_now.weekday() >= 5

            # Calendar context
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

            # Existing tasks context (what's already on the board)
            existing_work = [t.get("text","") for t in direct_context.get("workTasks",[]) if not t.get("done")][:8]
            existing_life = [t.get("text","") for t in direct_context.get("lifeTasks",[]) if not t.get("done")][:8]
            waiting = [t.get("text","") for t in direct_context.get("waitingItems",[]) if not t.get("done")][:5]

            existing_text = ""
            if existing_work:
                existing_text += "\nCurrent work tasks:\n" + "\n".join(f"- {t}" for t in existing_work)
            if existing_life:
                existing_text += "\nCurrent life tasks:\n" + "\n".join(f"- {t}" for t in existing_life)
            if waiting:
                existing_text += "\nWaiting on:\n" + "\n".join(f"- {t}" for t in waiting)

            # Scratch pad context
            scratch = direct_context.get("scratch", [])
            scratch_text = ""
            if scratch and any(s.strip() and s.strip() != "// jot things here" for s in scratch):
                scratch_text = "\nScratch pad notes:\n" + "\n".join(f"- {s}" for s in scratch[:10] if s.strip())

            # Time-of-day context
            if hour < 9:
                time_ctx = "It's early morning — good time for planning and high-priority items."
            elif hour < 12:
                time_ctx = "It's mid-morning — peak productivity window."
            elif hour < 14:
                time_ctx = "It's around lunch — consider lighter tasks or review."
            elif hour < 17:
                time_ctx = "It's afternoon — focus on completing open items before end of day."
            else:
                time_ctx = "It's evening — wrap up, plan for tomorrow, life admin."

            weekend_ctx = " It's the weekend — lean toward personal priorities." if is_weekend else ""

            if scope == "work":
                prompt = (
                    f"You are Alfredo, Todd's chief of staff. Today is {today_str}. {time_ctx}{weekend_ctx}\n\n"
                    f"Calendar:\n{cal_text}\n"
                    f"{existing_text}{scratch_text}\n\n"
                    "Generate Todd's WORK task list for today. You're his chief of staff — think about:\n"
                    "- What meetings need prep? What follow-ups are due?\n"
                    "- What's the most important thing to move forward today?\n"
                    "- Any deadlines approaching? Anything overdue from existing tasks?\n"
                    "- Don't duplicate existing tasks unless they need to be re-prioritized.\n"
                    "- Keep tasks specific and actionable (not vague like 'work on project').\n\n"
                    "Return ONLY a JSON array: [{\"text\": \"...\", \"done\": false, \"priority\": \"high|med|low\"}]\n"
                    "8-12 tasks. No explanation, no markdown, just JSON."
                )
            else:
                prompt = (
                    f"You are Alfredo, Todd's chief of staff. Today is {today_str}. {time_ctx}{weekend_ctx}\n\n"
                    f"Calendar:\n{cal_text}\n"
                    f"{existing_text}{scratch_text}\n\n"
                    "Generate Todd's LIFE / PERSONAL task list. As his chief of staff, think about:\n"
                    "- Household maintenance, errands, chores that are likely due\n"
                    "- Health: exercise, meal prep, appointments\n"
                    "- Relationships: check-ins, plans with friends/family\n"
                    "- Personal growth: reading, hobbies, side projects\n"
                    "- Admin: bills, subscriptions, groceries, car maintenance\n"
                    "- Seasonal/weather-appropriate suggestions (Seattle area)\n"
                    "- Don't duplicate existing life tasks.\n"
                    "- Mix practical must-dos with one or two 'treat yourself' items.\n\n"
                    "Return ONLY a JSON array: [{\"text\": \"...\", \"done\": false, \"priority\": \"high|med|low\"}]\n"
                    "6-10 tasks. No explanation, no markdown, just JSON."
                )

            req_data = json.dumps({"prompt": prompt}).encode()
            req = urllib.request.Request(
                "http://localhost:8420/chat",
                data=req_data,
                headers={"Content-Type": "application/json"},
                method="POST"
            )
            with urllib.request.urlopen(req, timeout=30) as r:
                result = json.loads(r.read())
            response_text = result.get("response", "")
            match = re.search(r'\[.*\]', response_text, re.DOTALL)
            if match:
                tasks = json.loads(match.group(0))
                tasks = [{"text": str(t.get("text", "")), "done": bool(t.get("done", False)),
                           "priority": t.get("priority", "med")}
                         for t in tasks if t.get("text")]
                return {"ok": True, "tasks": tasks, "source": "claude", "scope": scope}
        except Exception as ex:
            print(f"[suggest-tasks:{scope}] error: {ex}")
        return {"ok": False, "tasks": [], "source": "error", "scope": scope}

    def do_GET(self):
        if self.path == "/proxy/layout":
            # Return saved layouts (if any)
            try:
                with open("layouts.json") as f:
                    self._json(json.load(f))
            except FileNotFoundError:
                self._json({"layouts": {}, "schedules": {}, "updated": 0})
        elif self.path == "/proxy/health":
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
        elif self.path.startswith("/proxy/suggest-tasks"):
            scope = "work"
            if "?" in self.path:
                params = dict(p.split("=") for p in self.path.split("?")[1].split("&") if "=" in p)
                scope = params.get("scope", "work")
            self._json(self._suggest_tasks(scope))
        elif self.path.startswith("/proxy/voice-event"):
            # Return events since timestamp, or all recent
            since = 0
            if "?" in self.path:
                params = dict(p.split("=") for p in self.path.split("?")[1].split("&") if "=" in p)
                since = float(params.get("since", "0"))
            events = [e for e in voice_events if e["timestamp"] > since]
            self._json({"events": events, "muted": voice_muted})
        elif self.path == "/proxy/voice-mute":
            self._json({"muted": voice_muted})
        elif self.path == "/proxy/voice-activate":
            self._json({"active": voice_push_active})
        elif self.path == "/proxy/direct-context":
            snapshot = dict(direct_context)
            snapshot["calendar"] = get_merged_calendar().get("events", [])
            self._json(snapshot)
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
