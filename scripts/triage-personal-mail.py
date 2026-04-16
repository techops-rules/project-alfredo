#!/usr/bin/env python3
"""Triage personal-mail-latest.md into actionable candidates vs noise.

Personal email is ~95% marketing/retail. Signal: banking alerts,
tax/legal, medical, real people, Amazon order issues (not routine
ship/deliver). Writes to inbox/personal-triage-YYYY-MM-DD.md.
"""

import re
import sys

from mail_common import (
    VAULT, TODAY,
    parse_emails, extract_domain,
    bucket_entries, write_triage_report,
)

SOURCE = VAULT / "sources" / "personal-mail-latest.md"
OUTPUT = VAULT / "inbox" / f"personal-triage-{TODAY}.md"

# --- Category: BANKING / FINANCE ---

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

# --- Category: TAX / LEGAL ---

TAX_SENDERS = {
    "support.freetaxusa.com",
    "em1.turbotax.intuit.com",
}

TAX_SUBJECT_RE = re.compile(
    r"(?i)\b(?:tax\s+return|refund|irs|accepted|rejected|amended|"
    r"1099|w-?2|filing|efile)\b"
)

# --- Category: MEDICAL ---

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

# --- Category: SHIPPING / ORDERS ---

ORDER_ROUTINE_RE = re.compile(
    r"(?i)^(?:shipped|delivered|ordered|out\s+for\s+delivery|"
    r"your\s+.*(?:has\s+shipped|was\s+delivered|is\s+on\s+the\s+way))"
)

ORDER_PROBLEM_RE = re.compile(
    r"(?i)\b(?:delayed|lost|returned|refund|cancelled|issue|"
    r"undeliverable|missing|damage|replacement)\b"
)

# --- Category: NOISE ---

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

LINKEDIN_JOB_RE = re.compile(r"(?i)(?:profile\s+view|job.*apply|who'?s\s+hiring|opportunity)")
GOOGLE_SECURITY_RE = re.compile(r"(?i)(?:sign-?in|security|password|recovery|verification)")


def classify(entry: dict) -> tuple[str, str]:
    subj = entry["subject"]
    sender = entry["from"]
    domain = extract_domain(sender)

    if domain in BANKING_DOMAINS:
        if BANKING_PROMO_RE.search(subj):
            return "NOISE", "bank/finance promo"
        if BANKING_ALERT_RE.search(subj):
            return "ALERT", "banking/finance"
        return "FYI", "bank sender, no clear signal"

    if domain in TAX_SENDERS and TAX_SUBJECT_RE.search(subj):
        return "ALERT", "tax/legal"
    if domain in TAX_SENDERS:
        return "FYI", "tax sender, no action signal"

    if domain in MEDICAL_DOMAINS:
        if MEDICAL_PROMO_RE.search(subj):
            return "NOISE", "medical promo/survey"
        if MEDICAL_ALERT_RE.search(subj):
            return "ALERT", "medical/health"
        return "FYI", "medical sender, no clear signal"

    if domain == "accounts.google.com" and GOOGLE_SECURITY_RE.search(subj):
        return "ALERT", "Google account security"

    if domain in NOISE_DOMAINS:
        return "NOISE", f"marketing ({domain})"

    if NOISE_SENDERS_RE.search(sender):
        return "NOISE", "marketing/newsletter sender"

    if NOISE_SUBJECT_RE.search(subj):
        return "NOISE", "promotional subject"

    if "amazon.com" in domain:
        if ORDER_PROBLEM_RE.search(subj):
            return "ALERT", "Amazon order issue"
        if ORDER_ROUTINE_RE.search(subj):
            return "ORDER", "routine Amazon notification"
        return "FYI", "Amazon (unclassified)"

    if "usps" in sender.lower() or "usps" in domain:
        return "ORDER", "USPS tracking"

    if "linkedin.com" in domain:
        if LINKEDIN_JOB_RE.search(subj):
            return "NOISE", "LinkedIn job/profile alert"
        return "FYI", "LinkedIn notification"

    if "nextdoor.com" in domain:
        return "NOISE", "Nextdoor"

    if "facebookmail.com" in domain:
        return "FYI", "Facebook notification"

    if "ifttt.com" in domain:
        return "FYI", "IFTTT automation"

    if "nytimes.com" in domain and re.search(r"(?i)wordle|puzzle|game", subj):
        return "NOISE", "NYT games"

    if re.match(r"(?i)^(re|fwd):", subj):
        return "ACTION", "reply/forward thread"

    if ORDER_ROUTINE_RE.search(subj):
        return "ORDER", "routine shipping"

    return "FYI", "no signal detected"


def main():
    if not SOURCE.exists():
        print(f"No source file: {SOURCE}")
        sys.exit(1)

    text = SOURCE.read_text()
    entries = parse_emails(text)
    if not entries:
        print("No emails parsed.")
        sys.exit(0)

    buckets = bucket_entries(entries, classify)
    alerts = buckets.get("ALERT", [])
    actions = buckets.get("ACTION", [])
    orders = buckets.get("ORDER", [])
    fyi = buckets.get("FYI", [])
    noise = buckets.get("NOISE", [])

    write_triage_report(
        output_path=OUTPUT,
        title="Personal Email Triage",
        source_label="sources/personal-mail-latest.md",
        total=len(entries),
        header_note="Review alerts. Orders are logged quietly. Noise is filtered.",
        sections=[
            {"heading": "Alerts (banking, medical, tax, security)", "entries": alerts,
             "label": "alert", "style": "checkbox"},
            {"heading": "Action (real people, threads)", "entries": actions,
             "label": "action", "style": "checkbox"},
            {"heading": "Orders (routine, no action)", "entries": orders,
             "label": "order", "style": "plain"},
            {"heading": "FYI", "entries": fyi, "label": "FYI",
             "style": "plain", "show_reason": True},
            {"heading": f"Noise ({len(noise)} filtered)", "entries": noise,
             "label": "noise", "style": "count_only",
             "summary": "marketing/newsletter/promo emails filtered"},
        ],
    )

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
