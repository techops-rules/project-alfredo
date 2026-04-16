#!/usr/bin/env python3
"""Apply Pi vault_state back to ~/obsidian/todos/*.md.

Reads JSON on stdin with shape:
{"work":[{text,done,hot,line},...], "personal":[...], "version":N, ...}

Strategy (line-based, preserves headings + comments):
1. Toggles: find task by matching text (trimmed) — flip checkbox.
2. Adds (line=null): append under appropriate section.
3. Deletes: remove line by matching text.

For safety we only modify checkbox chars and append-new. We do NOT rewrite
line contents that the user has edited in-place.
"""
import json
import os
import re
import sys
import time

VAULT = os.path.expanduser("~/obsidian/todos")
FILES = {"work": "work.md", "personal": "personal.md"}
TASK_RE = re.compile(r"^(\s*-\s*\[)( |x|X)(\]\s*)(.+?)(\s*)$")

def apply_to_file(path, pi_tasks):
    """Given Pi's tasks, update the markdown file. Returns list of changes."""
    if not os.path.exists(path):
        with open(path, "w") as f:
            f.write("# Todos\n\n")
    with open(path) as f:
        lines = f.readlines()

    # Build a map of text -> (idx, current_done)
    current = {}
    for idx, raw in enumerate(lines):
        m = TASK_RE.match(raw.rstrip("\n"))
        if m:
            text = m.group(4).strip()
            current[text] = (idx, m.group(2).lower() == "x")

    changes = []

    # Pass 1: toggles — any Pi task that matches text but differs in done
    pi_texts = set()
    for pt in pi_tasks:
        pi_texts.add(pt["text"].strip())
        if pt["text"].strip() in current:
            idx, local_done = current[pt["text"].strip()]
            if bool(pt["done"]) != local_done:
                m = TASK_RE.match(lines[idx].rstrip("\n"))
                if m:
                    new_char = "x" if pt["done"] else " "
                    lines[idx] = f"{m.group(1)}{new_char}{m.group(3)}{m.group(4)}\n"
                    changes.append(f"toggle[{new_char}]: {pt['text'][:60]}")

    # Pass 2: deletes — tasks present in file but absent from Pi state
    local_texts = set(current.keys())
    removed = local_texts - pi_texts
    if removed:
        new_lines = []
        for raw in lines:
            m = TASK_RE.match(raw.rstrip("\n"))
            if m and m.group(4).strip() in removed:
                changes.append(f"delete: {m.group(4).strip()[:60]}")
                continue
            new_lines.append(raw)
        lines = new_lines

    # Pass 3: adds — Pi tasks with no match in file yet
    additions = [pt for pt in pi_tasks if pt["text"].strip() not in current and pt["text"].strip() not in removed]
    if additions:
        # Append under "## ➕ Added via kiosk" section at end
        if not any("Added via kiosk" in l for l in lines):
            if lines and not lines[-1].endswith("\n"):
                lines[-1] += "\n"
            lines.append("\n## ➕ Added via kiosk\n")
        for pt in additions:
            done_char = "x" if pt["done"] else " "
            lines.append(f"- [{done_char}] {pt['text']}\n")
            changes.append(f"add: {pt['text'][:60]}")

    if changes:
        tmp = path + ".tmp"
        with open(tmp, "w") as f:
            f.writelines(lines)
        os.rename(tmp, path)

    return changes

def main():
    payload = json.load(sys.stdin)
    all_changes = {}
    for scope, fname in FILES.items():
        pi_tasks = payload.get(scope, [])
        path = os.path.join(VAULT, fname)
        changes = apply_to_file(path, pi_tasks)
        if changes:
            all_changes[scope] = changes
    print(json.dumps({
        "applied_at": time.time(),
        "changes": all_changes,
    }, indent=2))

if __name__ == "__main__":
    main()
