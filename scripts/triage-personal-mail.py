#!/usr/bin/env python3
"""Triage personal-mail-latest.md into actionable candidates vs noise.

Personal email is ~95% marketing/retail. Signal: banking alerts,
tax/legal, medical, real people, Amazon order issues (not routine
ship/deliver). Writes to inbox/personal-triage-YYYY-MM-DD.md.
"""

import re
import sys
from datetime import datetime
from pathlib import Path

VAULT = Path.home() / "obsidian"
SOURCE = VAULT / "sources" / "personal-mail-latest.md"
TODAY = datetime.now().strftime("%Y-%m-%d")
OUTPUT = VAULT / "inbox" / f"personal-triage-{TODAY}.md"

# --- Category: BANKING / FINANCE (surface) ---

BANKING_DOMAINS = {
    "pnc.com", "e.pnc.com",
    "apcifcu.org",
    "notifications.acorns.com",
    "emails.creditonebank.com",
    "e.affirm.com",
    "e.upgrade.com",
}

BANKING_ALERT_RE = re.compile(
    r"(?i)\b(?:deposit.*credited|withdraw|payment\s+(?:due|received|posted)|"
    r"available\s+balance|fraud\s+alert|suspicious|overdraft|"
    r"statement\s+(?:is\s+)?(?:ready|available|now)|"
    r"account.*(?:locked|suspended|closed)|security\s+alert)\b"
)

BANKING_PROMO_RE = re.compile(
    r"(?i)(?:credit\s+card\s+lets|loan\s+invitation|vacation\s+could\s+be|"
    r"take\s+some\s+time\s+off|rewarded?\s+for\s+referr|"
    r"challenge\s+starts|celebrate|youth\s+week|"
    r"apply\s+now|pre-?approved|limited\s+offer)"
)

# --- Category: TAX / LEGAL / GOVERNMENT (surface) ---

TAX_SENDERS = {
    "support.freetaxusa.com",
    "em1.turbotax.intuit.com",
}

TAX_SUBJECT_RE = re.compile(
    r"(?i)\b(?:tax\s+return|refund|irs|accepted|rejected|amended|"
    r"1099|w-?2|filing|efile)\b"
)

# --- Category: MEDICAL (surface) ---

MEDICAL_DOMAINS = {
    "orders.express-scripts.com",
    "email.rula.com",
    "columbia.care",
}

MEDICAL_ALERT_RE = re.compile(
    r"(?i)\b(?:prescription|refill|order\s+your|appointment|lab\s+results?|"
    r"doctor|pharmacy|copay|insurance\s+claim|ready\s+to\s+pick\s+up)\b"
)

MEDICAL_PROMO_RE = re.compile(
    r"(?i)(?:how\s+many\s+stars|survey|rate\s+us|review|wheel\s+wednesday|"
    r"sale|% off|promo|special\s+offer)"
)

# --- Category: SHIPPING / ORDERS (quiet unless problem) ---

ORDER_ROUTINE_RE = re.compile(
    r"(?i)^(?:shipped|delivered|ordered|out\s+for\s+delivery|"
    r"your\s+.*(?:has\s+shipped|was\s+delivered|is\s+on\s+the\s+way))"
)

ORDER_PROBLEM_RE = re.compile(
    r"(?i)\b(?:delayed|lost|returned|refund|cancelled|issue|"
    r"undeliverable|missing|damage|replacement)\b"
)

# --- Category: NOISE (marketing, retail, newsletters) ---

NOISE_DOMAINS = {
    "e.newyorktimes.com", "nytimes.com",
    "emails.macys.com", "email.surlatable.com",
    "email.sportsmansguide.com", "enews.opticsplanet.com",
    "h.emailhsn.com", "mail.hobbyking.com",
    "email-marriott.com", "emailinfo.dunkinrewards.com",
    "email.nfl.com", "email.feverup.com", "email.famousfootwear.com",
    "email.bestbuy.com", "em.venetianlasvegas.com", "em.target.com",
    "em.aritzia.com", "eg.vrbo.com", "eg.hotels.com",
    "e.harborfreight.com", "e.allegiant.com", "e.academy.com",
    "e.ufc.com", "e.usa.experian.com", "e.equifax.com",
    "d.sportsmans.com", "d.slickdeals.net",
    "send.magbak.com", "cdnnsports.com",
    "enews.united.com", "us.olight.com",
    "trueshotammo.com", "dealwiki.net", "comfrt.com",
    "hellotushy.com", "keychron.com", "kingandfifth.com",
    "exxonandmobilrewardsplus.com", "emails.hertz.com",
    "highlights.espnmail.com", "palmettostatearmory.com",
    "insideapple.apple.com", "dontsleeponai.com",
    "mail1.fsastore.com", "joshshapiro.org",
    "caclv.org", "ushcommunities.org", "apothecarium.com",
    "ihatestevensinger.com",
    "beistravel.com",
    "vesta.threadloom.news",
}

NOISE_SENDERS_RE = re.compile(
    r"(?i)(?:no-?reply|noreply|donotreply|newsletter|marketing|"
    r"promo|campaign|digest@|newsdigest|rewards|survey)"
)

NOISE_SUBJECT_RE = re.compile(
    r"(?i)(?:% off|save \$|free shipping|limited time|flash sale|"
    r"don'?t miss|last chance|exclusive|just dropped|"
    r"best seller|new arrival|clearance|coupon|promo code|"
    r"birthday month|sparkle|timeless|going fast|"
    r"free hazmat|ends tonight|save up to \$|"
    r"sweepstakes|hiring|opportunity to apply|"
    r"robot mower|sofa table|locked in|"
    r"\$\d+\s*\|.*\$\d+|this wasn'?t just)"
)

# --- Category: REAL PEOPLE ---

REAL_PERSON_RE = re.compile(
    r"(?i)\b(?:todd|hey|hi\s+todd|fwd:|re:)\b"
)

# LinkedIn job alerts — FYI not action
LINKEDIN_JOB_RE = re.compile(r"(?i)(?:profile\s+view|job.*apply|who'?s\s+hiring|opportunity)")

# Google account — might be security
GOOGLE_SECURITY_RE = re.compile(r"(?i)(?:sign-?in|security|password|recovery|verification)")


def parse_emails(text: str) -> list[dict]:
    entries = []
    current = None
    for line in text.split("\n"):
        line = line.strip()
        if not line:
            continue
        if line.startswith("## "):
            if current:
                entries.append(current)
            current = {"subject": line[3:].strip(), "from": "", "date": "", "read": ""}
        elif current:
            if line.startswith("- **From:**"):
                current["from"] = line.split("**From:**")[1].strip()
            elif line.startswith("- **Date:**"):
                current["date"] = line.split("**Date:**")[1].strip()
            elif line.startswith("- **Read:**"):
                current["read"] = line.split("**Read:**")[1].strip().lower()
    if current:
        entries.append(current)
    return entries


def extract_domain(sender: str) -> str:
    match = re.search(r"<([^>]+)>", sender)
    addr = match.group(1) if match else sender
    parts = addr.split("@")
    return parts[1].lower() if len(parts) == 2 else ""


def classify(entry: dict) -> tuple[str, str]:
    subj = entry["subject"]
    sender = entry["from"]
    domain = extract_domain(sender)

    # Banking: promo from financial domain → noise, alert only on real signals
    if domain in BANKING_DOMAINS:
        if BANKING_PROMO_RE.search(subj):
            return "NOISE", "bank/finance promo"
        if BANKING_ALERT_RE.search(subj):
            return "ALERT", "banking/finance"
        return "FYI", "bank sender, no clear signal"

    # Tax / legal
    if domain in TAX_SENDERS and TAX_SUBJECT_RE.search(subj):
        return "ALERT", "tax/legal"
    if domain in TAX_SENDERS:
        return "FYI", f"tax sender, no action signal"

    # Medical: promo/survey → noise, real health items → alert
    if domain in MEDICAL_DOMAINS:
        if MEDICAL_PROMO_RE.search(subj):
            return "NOISE", "medical promo/survey"
        if MEDICAL_ALERT_RE.search(subj):
            return "ALERT", "medical/health"
        return "FYI", "medical sender, no clear signal"

    # Google account security
    if domain == "accounts.google.com" and GOOGLE_SECURITY_RE.search(subj):
        return "ALERT", "Google account security"

    # Known noise domains
    if domain in NOISE_DOMAINS:
        return "NOISE", f"marketing ({domain})"

    # Noise sender patterns
    if NOISE_SENDERS_RE.search(sender):
        return "NOISE", "marketing/newsletter sender"

    # Noise subject patterns
    if NOISE_SUBJECT_RE.search(subj):
        return "NOISE", "promotional subject"

    # Amazon — routine orders are quiet, problems escalate
    if "amazon.com" in domain:
        if ORDER_PROBLEM_RE.search(subj):
            return "ALERT", "Amazon order issue"
        if ORDER_ROUTINE_RE.search(subj):
            return "ORDER", "routine Amazon notification"
        return "FYI", "Amazon (unclassified)"

    # USPS / shipping — routine is quiet
    if "usps" in sender.lower() or "usps" in domain:
        return "ORDER", "USPS tracking"

    # LinkedIn
    if "linkedin.com" in domain:
        if LINKEDIN_JOB_RE.search(subj):
            return "NOISE", "LinkedIn job/profile alert"
        return "FYI", "LinkedIn notification"

    # Nextdoor
    if "nextdoor.com" in domain:
        return "NOISE", "Nextdoor"

    # Facebook
    if "facebookmail.com" in domain:
        return "FYI", "Facebook notification"

    # IFTTT
    if "ifttt.com" in domain:
        return "FYI", "IFTTT automation"

    # NYT games (wordle etc)
    if "nytimes.com" in domain and re.search(r"(?i)wordle|puzzle|game", subj):
        return "NOISE", "NYT games"

    # Re: or Fwd: from non-noise domain — likely a real person
    if re.match(r"(?i)^(re|fwd):", subj):
        return "ACTION", "reply/forward thread"

    # Catch remaining known patterns
    if ORDER_ROUTINE_RE.search(subj):
        return "ORDER", "routine shipping"

    # Default: FYI
    return "FYI", "no signal detected"


def main():
    if not SOURCE.exists():
        print(f"No source file: {SOURCE}")
        sys.exit(1)

    text = SOURCE.read_text().replace("\r\n", "\n").replace("\r", "\n")
    entries = parse_emails(text)
    if not entries:
        print("No emails parsed.")
        sys.exit(0)

    alerts = []
    actions = []
    orders = []
    fyi = []
    noise = []

    for entry in entries:
        cat, reason = classify(entry)
        entry["_category"] = cat
        entry["_reason"] = reason
        {"ALERT": alerts, "ACTION": actions, "ORDER": orders, "FYI": fyi, "NOISE": noise}[cat].append(entry)

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)

    lines = [
        f"# Personal Email Triage — {TODAY}",
        "",
        f"Source: `sources/personal-mail-latest.md`",
        f"Processed: {datetime.now().strftime('%Y-%m-%d %H:%M')}",
        f"Total: {len(entries)} emails → {len(alerts)} alert, {len(actions)} action, "
        f"{len(orders)} order, {len(fyi)} FYI, {len(noise)} noise",
        "",
        "**Review alerts. Orders are logged quietly. Noise is filtered.**",
        "",
    ]

    if alerts:
        lines.append("## Alerts (banking, medical, tax, security)")
        lines.append("")
        for e in alerts:
            lines.append(f"- [ ] {e['subject']}")
            lines.append(f"  - From: {e['from']}")
            lines.append(f"  - Why: {e['_reason']}")
            lines.append("")

    if actions:
        lines.append("## Action (real people, threads)")
        lines.append("")
        for e in actions:
            lines.append(f"- [ ] {e['subject']}")
            lines.append(f"  - From: {e['from']}")
            lines.append(f"  - Why: {e['_reason']}")
            lines.append("")

    if orders:
        lines.append("## Orders (routine, no action)")
        lines.append("")
        for e in orders:
            lines.append(f"- {e['subject']}")
        lines.append("")

    if fyi:
        lines.append("## FYI")
        lines.append("")
        for e in fyi:
            lines.append(f"- {e['subject']} — {e['_reason']}")
        lines.append("")

    if noise:
        lines.append(f"## Noise ({len(noise)} filtered)")
        lines.append("")
        lines.append(f"_{len(noise)} marketing/newsletter/promo emails filtered._")
        lines.append("")

    OUTPUT.write_text("\n".join(lines))

    print(f"Triage complete: {OUTPUT}")
    print(f"  {len(alerts)} alert | {len(actions)} action | {len(orders)} order | {len(fyi)} FYI | {len(noise)} noise")

    if alerts:
        print("\nAlerts:")
        for e in alerts:
            print(f"  ⚠ {e['subject']} ({e['_reason']})")
    if actions:
        print("\nActions:")
        for e in actions:
            print(f"  → {e['subject']} ({e['_reason']})")


if __name__ == "__main__":
    main()
