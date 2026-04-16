#!/usr/bin/env python3
"""Fetch today's Google Calendar events via API and push to Pi kiosk.

First run opens browser for OAuth. Token saved to ~/.config/alfredo/
for unattended use by LaunchAgent.
"""

import json
import os
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

from google.auth.transport.requests import Request
from google.oauth2.credentials import Credentials
from google_auth_oauthlib.flow import InstalledAppFlow
from googleapiclient.discovery import build

import requests as http_requests

CONFIG_DIR = Path.home() / ".config" / "alfredo"
CREDS_FILE = CONFIG_DIR / "google-credentials.json"
TOKEN_FILE = CONFIG_DIR / "google-token.json"
SCOPES = ["https://www.googleapis.com/auth/calendar.readonly"]

KIOSK_HOST = "pihub.local"
KIOSK_PORT = 8430
CALENDAR_ID = "tmichel@omnidian.com"


def get_google_creds():
    """Load or refresh Google OAuth credentials."""
    creds = None

    if TOKEN_FILE.exists():
        creds = Credentials.from_authorized_user_file(str(TOKEN_FILE), SCOPES)

    if not creds or not creds.valid:
        if creds and creds.expired and creds.refresh_token:
            creds.refresh(Request())
        else:
            if not CREDS_FILE.exists():
                print(f"Missing {CREDS_FILE} — set up OAuth in Google Cloud Console", file=sys.stderr)
                sys.exit(1)
            flow = InstalledAppFlow.from_client_secrets_file(str(CREDS_FILE), SCOPES)
            creds = flow.run_local_server(port=0)

        TOKEN_FILE.write_text(creds.to_json())

    return creds


def fetch_events(creds) -> list:
    """Fetch today + tomorrow events from Google Calendar API."""
    service = build("calendar", "v3", credentials=creds)

    now = datetime.now(timezone.utc)
    start = now.replace(hour=0, minute=0, second=0, microsecond=0)
    end = start + timedelta(days=2)

    result = service.events().list(
        calendarId=CALENDAR_ID,
        timeMin=start.isoformat(),
        timeMax=end.isoformat(),
        singleEvents=True,
        orderBy="startTime",
        maxResults=50,
    ).execute()

    events = []
    for item in result.get("items", []):
        if item.get("status") == "cancelled":
            continue

        start_raw = item.get("start", {})
        end_raw = item.get("end", {})

        is_allday = "date" in start_raw and "dateTime" not in start_raw
        start_str = start_raw.get("dateTime") or start_raw.get("date", "")
        end_str = end_raw.get("dateTime") or end_raw.get("date", "")

        start_dt = parse_gcal_dt(start_str)
        end_dt = parse_gcal_dt(end_str)

        attendees = item.get("attendees", [])
        my_status = "needsAction"
        for a in attendees:
            if a.get("self"):
                my_status = a.get("responseStatus", "needsAction")
                break

        events.append({
            "title": item.get("summary", "(no title)"),
            "startTime": start_str,
            "endTime": end_str,
            "start": start_str,
            "end": end_str,
            "startEpoch": int(start_dt.timestamp()) if start_dt else 0,
            "endEpoch": int(end_dt.timestamp()) if end_dt else 0,
            "isAllDay": is_allday,
            "allDay": is_allday,
            "location": item.get("location", ""),
            "calendar": "Omnidian",
            "source": "google-api",
            "status": item.get("status", "confirmed"),
            "myStatus": my_status,
            "conferenceUrl": item.get("conferenceData", {}).get("entryPoints", [{}])[0].get("uri", "") if item.get("conferenceData") else "",
            "attendeeCount": len(attendees),
        })

    return events


def parse_gcal_dt(raw):
    """Parse Google Calendar datetime string."""
    if not raw:
        return None
    try:
        if "T" in raw:
            from dateutil.parser import parse as dp
            return dp(raw)
        else:
            return datetime.strptime(raw, "%Y-%m-%d").replace(tzinfo=timezone.utc)
    except Exception:
        return None


def push_to_kiosk(events):
    """POST events to kiosk serve.py."""
    url = f"http://{KIOSK_HOST}:{KIOSK_PORT}/proxy/calendar"
    payload = {
        "events": events,
        "source": "mac-google-api-push",
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }
    try:
        resp = http_requests.post(url, json=payload, timeout=10)
        print(f"Pushed {len(events)} events to kiosk: {resp.status_code}")
    except http_requests.ConnectionError:
        print(f"Kiosk unreachable at {url} — events fetched but not pushed")


def main():
    creds = get_google_creds()
    print("Fetching calendar via Google API...")
    events = fetch_events(creds)
    print(f"Got {len(events)} events for today+tomorrow")

    for e in events:
        day = e["start"][:10]
        time_part = e["start"][11:16] if not e["allDay"] else "all-day"
        status = f" [{e['myStatus']}]" if e["myStatus"] != "accepted" else ""
        print(f"  {day} {time_part} {e['title']}{status}")

    push_to_kiosk(events)


if __name__ == "__main__":
    main()
