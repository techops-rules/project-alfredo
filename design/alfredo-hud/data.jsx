// Mock data for alfredo. Time is "now" = Fri Apr 17, 2026, 8:42am.
// Persona: deadpan, mildly mean, accurate.

const NOW = new Date('2026-04-17T08:42:00');

const DAILY_BRIEF = {
  generatedAt: '07:58',
  headline: "Three things matter today. The rest is noise.",
  mood: "You slept 5h 12m. Brace.",
  items: [
    {
      rank: 1,
      label: "Ship the Q2 forecast to Renata by EOD",
      why: "She's asked twice. Second ask was 'gentle.' The next won't be.",
      confidence: 0.94,
      source: "gmail · @renata · 2 threads",
      tag: "WORK",
    },
    {
      rank: 2,
      label: "10:00 — QAQC sync. You owe the agenda.",
      why: "Last week's blockers were never resolved. Pull them forward.",
      confidence: 0.81,
      source: "calendar + obsidian/qaqc.md",
      tag: "WORK",
    },
    {
      rank: 3,
      label: "Pick up Mira from school at 15:15",
      why: "Half-day. You forgot last time. We're not doing that again.",
      confidence: 0.99,
      source: "icloud · family",
      tag: "LIFE",
    },
  ],
  swept: [
    { label: "AWS billing alert", verdict: "noise", confidence: 0.88 },
    { label: "12 Slack mentions in #general", verdict: "noise", confidence: 0.72 },
    { label: "LinkedIn 'You appeared in 4 searches'", verdict: "noise", confidence: 0.99 },
    { label: "Calendly bot retry", verdict: "noise", confidence: 0.94 },
  ],
};

const PULSE = {
  meeting: "QAQC weekly",
  startsAt: "10:00",
  inMinutes: 78,
  attendees: ["You", "Renata K.", "David O.", "Priya S."],
  lastDiscussion: "Cycle-time regression on batch 41. David said he'd retest with the new fixture.",
  openQuestions: [
    "Did the new fixture actually move the needle?",
    "Are we still escalating to Manuf. on the 22nd?",
  ],
  prep: [
    "Pull batch-41 chart from prior thread",
    "Draft 1-line ask for Manuf. escalation",
  ],
  confidence: 0.76,
};

const CALENDAR = [
  { time: "10:00", dur: "30m", title: "QAQC weekly", where: "Zoom", tag: "WORK", soon: true },
  { time: "11:30", dur: "45m", title: "1:1 — Priya", where: "Walk", tag: "WORK" },
  { time: "13:00", dur: "30m", title: "Lunch (block)", where: "—", tag: "LIFE", soft: true },
  { time: "15:15", dur: "—",   title: "Pick up Mira", where: "Lincoln Elem.", tag: "LIFE", hard: true },
  { time: "16:00", dur: "60m", title: "Forecast review", where: "Renata's office", tag: "WORK" },
  { time: "19:00", dur: "—",   title: "Dinner w/ Sam", where: "Quince", tag: "LIFE" },
  // tomorrow
  { time: "Sat 09:00", dur: "120m", title: "Mira soccer", where: "Field 3", tag: "LIFE", day: 1 },
  { time: "Sat 14:00", dur: "—",    title: "Hardware store", where: "—", tag: "LIFE", day: 1, soft: true },
];

const INBOX = [
  {
    from: "Renata Kovac",
    email: "renata@omnidian.com",
    subject: "Re: Q2 forecast — need by EOD",
    snippet: "Pinging again — need a number to take into the board pre-read tonight.",
    body: "Todd,\n\nPinging again — I need a concrete number to take into the board pre-read tonight at 7pm. Even a confidence interval is fine; I just can't go in with nothing.\n\nIf $4.2M is still your anchor, I'll run with that. Let me know either way by 5.\n\nR.",
    classified: "ESCALATE",
    confidence: 0.96,
    age: "12m",
  },
  {
    from: "David Oyelowo",
    email: "david.o@omnidian.com",
    subject: "Batch 41 retest results",
    snippet: "Fixture didn't help. Chart attached. Want to talk before QAQC.",
    body: "Hey Todd,\n\nRan the batch-41 retest with the new fixture this morning. Delta is within noise — fixture didn't move the needle. Chart attached.\n\nWant to grab 5 min before QAQC to align on the story? I'd rather we pitch this together than have Priya ask separately.\n\n— David",
    classified: "ESCALATE",
    confidence: 0.91,
    age: "1h",
  },
  {
    from: "Stripe",
    email: "receipts@stripe.com",
    subject: "Your invoice for April",
    snippet: "Receipt attached. No action required.",
    body: "Your April 2026 invoice is ready.\n\nAmount: $47.00\nStatus: Paid\nInvoice #INV-2026-0417\n\nNo action required. Receipt attached.",
    classified: "FYI",
    confidence: 0.98,
    age: "3h",
  },
  {
    from: "Notion",
    email: "no-reply@notion.so",
    subject: "Weekly digest: 14 pages updated",
    snippet: "Here's what your team worked on…",
    body: "Your workspace updates for the week of Apr 10–17:\n\n• 14 pages updated\n• 3 new pages created\n• 6 tasks completed\n\nTop contributors: you, Priya S., David O.",
    classified: "IGNORE",
    confidence: 0.93,
    age: "5h",
  },
  {
    from: "Sam (partner)",
    email: "sam@personal.example",
    subject: "tonight",
    snippet: "8pm Quince. confirmed. don't forget.",
    body: "8pm Quince. confirmed. don't forget.\n\nalso — mira's school thing is next wed, not thur like I said. just got the email.",
    classified: "FYI",
    confidence: 0.84,
    age: "6h",
  },
  {
    from: "AWS Billing",
    email: "no-reply@aws.amazon.com",
    subject: "Spend alert: $42 over budget",
    snippet: "Your account has exceeded the configured threshold.",
    body: "Your AWS account has exceeded the configured monthly threshold of $150.\n\nCurrent spend: $192.14\nTop services: EC2 ($121), S3 ($34), Route53 ($14)\n\nReview at console.aws.amazon.com/billing.",
    classified: "IGNORE",
    confidence: 0.71,
    age: "8h",
  },
];

const PROJECTS = [
  {
    name: "QAQC.PROCESS",
    state: "ACTIVE",
    health: "yellow",
    last: "Cycle-time regression unresolved",
    next: "Pull batch-41 chart for 10:00",
    open: 3,
    blockers: 1,
    owner: "you",
  },
  {
    name: "Q2.FORECAST",
    state: "DUE.TODAY",
    health: "red",
    last: "Renata pinged twice",
    next: "Draft number, send by 17:00",
    open: 2,
    blockers: 0,
    owner: "you",
  },
  {
    name: "ALFREDO.SELF",
    state: "ACTIVE",
    health: "green",
    last: "Wired iCloud cal yesterday",
    next: "Add Slack ingest",
    open: 5,
    blockers: 0,
    owner: "you",
  },
  {
    name: "HOUSE.ROOF",
    state: "STALLED",
    health: "yellow",
    last: "3 contractor quotes received",
    next: "Pick one. You've been picking one for 11 days.",
    open: 1,
    blockers: 0,
    owner: "you+sam",
  },
  {
    name: "EUROTRIP",
    state: "ACTIVE",
    health: "green",
    last: "Booked Lisbon → Porto train",
    next: "Pack list, walking shoes, EU sim card",
    open: 7,
    blockers: 0,
    owner: "you+sierra",
  },
];

// Scratch items are triage-ready objects. Seeded with realistic content that
// exercises each classifier branch (phone, address, url, date, project-match).
const SCRATCH = [
  { id: 'seed-1', text: "ask david: did fixture help?", addedAt: Date.now() - 3600000, state: 'raw' },
  { id: 'seed-2', text: "renata wants forecast by EOD — anchor at $4.2M", addedAt: Date.now() - 1800000, state: 'raw' },
  { id: 'seed-3', text: "need better walking shoes for the eurotrip", addedAt: Date.now() - 600000, state: 'raw' },
  { id: 'seed-4', text: "tommy 610-555-0142 call about quote", addedAt: Date.now() - 300000, state: 'raw' },
];

// Rotating hero headlines. Simple, direct, somewhat helpful, encouraging-with-teeth.
const HEADLINES = [
  "three things matter today. the rest is noise.",
  "less thinking, more doing.",
  "one thing at a time. one.",
  "show up, make a dent, go home.",
  "the list doesn't shrink by staring at it.",
  "two hours of real work beats a full day of busy.",
  "fewer tabs. start there.",
  "inbox zero is a myth. next action isn't.",
  "the meeting doesn't prep itself.",
  "pick the hard one first. you'll coast after.",
  "call it done at 80%. ship.",
  "no one is grading the difficulty.",
  "future-you will thank current-you. eventually.",
  "you've got this. probably.",
  "the day started. you can keep up.",
  "progress, not performance.",
];

// Monday-voice micro-facts for the iOS hero. Kept short, mildly mean, accurate.
const MICRO_FACTS = [
  "you slept 5h 12m. brace.",
  "2,400 steps. legs are drafting a resignation letter.",
  "3 tasks shipped yesterday. respectable.",
  "coffee #2 was at 10:14. we're tracking.",
  "inbox: 6 live threads. four can wait.",
  "last water log was 11:47. it's 14:02.",
  "screen time: 4h 30m before noon. a choice.",
  "EUROTRIP · 14 days out. pack list is empty.",
];

// Persona lines for CLAUDE.TTY
const TTY_GREETINGS = [
  "alfredo online. you have 78 minutes until you embarrass yourself in QAQC.",
  "good morning. your inbox is doing the thing again.",
  "you're up. three things matter. ask me which.",
  "ready. try not to open slack first.",
];

// Confidence dot color ramp
const confColor = (c) => {
  if (c >= 0.9) return 'var(--accent)';
  if (c >= 0.75) return 'var(--accent-dim)';
  if (c >= 0.5) return 'var(--muted)';
  return 'var(--muted-dim)';
};

Object.assign(window, {
  NOW, DAILY_BRIEF, PULSE, CALENDAR, INBOX, PROJECTS, SCRATCH, TTY_GREETINGS, confColor,
});
