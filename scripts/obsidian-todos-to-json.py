#!/usr/bin/env python3
"""Parse ~/obsidian/todos/*.md into JSON shape the kiosk expects.

Output schema:
{
  "work":     [{"text": "...", "done": false, "hot": true, "line": 3}, ...],
  "personal": [...],
  "source_mtime_work":     1234567890.0,
  "source_mtime_personal": 1234567890.0,
  "generated_at":          1234567890.0
}
"""
import json
import os
import re
import sys
import time

VAULT = os.path.expanduser("~/obsidian/todos")
FILES = {"work": "work.md", "personal": "personal.md"}

TASK_RE = re.compile(r"^\s*-\s*\[( |x|X)\]\s*(.+?)\s*$")
HEADING_RE = re.compile(r"^#+\s+(.+?)\s*$")
HOT_HEADING_RE = re.compile(r"(🔥|\bHOT\b)", re.IGNORECASE)

def parse_file(path):
    if not os.path.exists(path):
        return [], 0.0
    mtime = os.path.getmtime(path)
    tasks = []
    in_hot_section = False
    with open(path) as f:
        for i, raw in enumerate(f, start=1):
            h = HEADING_RE.match(raw)
            if h:
                in_hot_section = bool(HOT_HEADING_RE.search(h.group(1)))
                continue
            m = TASK_RE.match(raw)
            if not m:
                continue
            done = m.group(1).lower() == "x"
            text = m.group(2).strip()
            hot = in_hot_section or bool(HOT_HEADING_RE.search(text))
            tasks.append({"text": text, "done": done, "hot": hot, "line": i})
    return tasks, mtime

def main():
    out = {"generated_at": time.time()}
    for scope, fname in FILES.items():
        tasks, mtime = parse_file(os.path.join(VAULT, fname))
        out[scope] = tasks
        out[f"source_mtime_{scope}"] = mtime
    json.dump(out, sys.stdout, indent=2)
    sys.stdout.write("\n")

if __name__ == "__main__":
    main()
