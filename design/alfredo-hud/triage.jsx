// Triage engine for scratch notes.
// Flow: raw text → entity-regex pass → LLM classifier → routed to store
//       → tap-to-inspect → user can reclassify or approve calendar writes.
//
// Everything here is side-effect-free except the LLM call. Route side-effects
// happen in index.html via the scratch reducer.

// ── Priority system (P0–P4) ────────────────────────────────────────────────
// P0: critical, max 5 live at once, top of hot list
// P1: important, fills slots if no P0s remain
// P2: fyi / good to know, not urgent
// P3: backlog, no timeline but intend to do
// P4: someday, lowest signal
const PRIORITY_META = {
  P0: { label: 'P0', color: 'var(--bad)', glow: 'rgba(238,108,108,0.4)', desc: 'critical' },
  P1: { label: 'P1', color: 'var(--warn)', glow: 'rgba(245,185,105,0.35)', desc: 'important' },
  P2: { label: 'P2', color: 'var(--accent)', glow: 'rgba(138,180,248,0.3)', desc: 'fyi' },
  P3: { label: 'P3', color: 'var(--muted)', glow: 'rgba(92,101,115,0.2)', desc: 'backlog' },
  P4: { label: 'P4', color: 'var(--muted-dim)', glow: 'transparent', desc: 'someday' },
};
const P0_CAP = 5;

// Parse "p0" / "p4" at the start or end of a note. Returns { text, priority }
// with the tag stripped from text and priority upper-cased, or null if none.
function parsePriority(input) {
  const re = /(?:^\s*(p[0-4])\b\s*)|(?:\s+(p[0-4])\s*$)/i;
  const m = input.match(re);
  if (!m) return { text: input, priority: null };
  const pri = (m[1] || m[2]).toUpperCase();
  const cleaned = input.replace(re, '').trim();
  return { text: cleaned || input, priority: pri };
}

// LLM priority suggester — uses Sonnet with full user context so the rating
// actually weighs active work, existing P0 load, known user preferences, and
// today's commitments, not just the note in isolation.
async function suggestPriorityLLM(text, context = {}) {
  const apiKey = localStorage.getItem('alfredo:anthropic_key');
  if (!apiKey || !window.streamClaude) return null;

  const now = new Date();
  const existingP0s = (context.scratch || []).filter(s => s.priority === 'P0').map(s => s.text);
  const existingP1s = (context.scratch || []).filter(s => s.priority === 'P1').slice(0, 8).map(s => s.text);
  const todos = (context.todos || []).slice(-10).map(t => t.text);
  const todayCal = (context.calendar || []).filter(c => !c.day).map(c => `${c.time} ${c.title}`);
  const briefTop = (context.brief?.items || []).map(i => `#${i.rank} ${i.label}`);

  const sys = [
    'You rate the priority of a single scratchpad note for Todd, an ADHD-inattentive operator.',
    '',
    'LEVELS:',
    '  P0 — critical, today. Must be done or the day fails. Reserved (cap 5). Usually a hard deadline, a person blocked on you, or something that will actively hurt if missed.',
    '  P1 — important, this week. Matters, but has slack. Ship-by-Friday kinds of things.',
    '  P2 — fyi / routine. Good to know, not urgent. Would be fine to do next week.',
    '  P3 — backlog. Intend to do eventually. No deadline pressure.',
    '  P4 — someday. Low signal. Would be nice but honestly may never happen.',
    '',
    'USER CONTEXT (Todd):',
    '  ADHD-inattentive operator. Work at Omnidian (solar O&M, PM role). Personal commitments to Sierra (partner) and Mira (kid).',
    '  Deadpan Monday-style assistant persona. Likes concrete, decisive answers over hedging.',
    '',
    'CURRENT STATE (today = ' + now.toLocaleDateString('en-US', { weekday: 'long', month: 'short', day: 'numeric' }) + '):',
    briefTop.length ? '  Daily brief top: ' + briefTop.join(' · ') : '',
    existingP0s.length ? '  Existing P0s (' + existingP0s.length + '/5 used): ' + existingP0s.join(' | ') : '  No current P0s.',
    existingP1s.length ? '  Existing P1s: ' + existingP1s.join(' | ') : '',
    todayCal.length ? '  Today\'s calendar: ' + todayCal.join(' · ') : '',
    todos.length ? '  Recent todos: ' + todos.join(' | ') : '',
    context.projects ? '  Active projects: ' + context.projects.map(p => `${p.name}(${p.state} · next: ${p.next})`).join(' | ') : '',
    '',
    'RULES:',
    '  - Weigh AGAINST the current load. If 4 P0s are active, a 5th needs to be genuinely critical.',
    '  - If a person is waiting on Todd (named sender, second ping, partner/kid): lean P0 or P1.',
    '  - If it\'s reference / "someday" flavor: P3 or P4.',
    '  - Prefer to err lower — Todd already has too many "important" things.',
    '',
    'Return ONE token only: P0, P1, P2, P3, or P4. No prose.',
    '',
    'NOTE TO RATE: ' + text,
  ].filter(Boolean).join('\n');

  try {
    let out = '';
    await window.streamClaude({
      apiKey, system: sys, userText: 'rate this note',
      onDelta: (c) => { out += c; },
      model: 'claude-sonnet-4-6',
      maxTokens: 12,
    });
    const match = out.trim().toUpperCase().match(/P[0-4]/);
    return match ? match[0] : null;
  } catch {
    return null;
  }
}

// ── Entity detection ────────────────────────────────────────────────────────
// Phone numbers: US-style with optional country, separators, extensions.
const PHONE_RE = /(\+?1[-.\s]?)?\(?\d{3}\)?[-.\s]?\d{3}[-.\s]?\d{4}/g;
const URL_RE = /\bhttps?:\/\/[^\s]+/gi;
// Loose "looks like a street address" — num + words + suffix
const ADDRESS_RE = /\b\d{1,5}\s+([A-Z][\w.]*\s+){1,4}(street|st|avenue|ave|road|rd|blvd|boulevard|drive|dr|lane|ln|way|court|ct|place|pl|parkway|pkwy|hwy|highway)\b[\w\s,.]*/gi;
// Date/time phrases — very loose, lets the classifier refine
const DATE_HINT_RE = /\b(monday|tuesday|wednesday|thursday|friday|saturday|sunday|mon|tue|wed|thu|fri|sat|sun|today|tomorrow|tonight|this (morning|afternoon|evening|weekend)|next (week|month|monday|tuesday|wednesday|thursday|friday|saturday|sunday)|\d{1,2}\s?(am|pm|:\d\d)|\d{1,2}\/\d{1,2}(\/\d{2,4})?)\b/gi;

function detectEntities(text) {
  const phones = Array.from(text.matchAll(PHONE_RE)).map(m => m[0]);
  const urls = Array.from(text.matchAll(URL_RE)).map(m => m[0]);
  const addresses = Array.from(text.matchAll(ADDRESS_RE)).map(m => m[0].trim());
  const dates = Array.from(text.matchAll(DATE_HINT_RE)).map(m => m[0]);
  return {
    phones: [...new Set(phones)],
    urls: [...new Set(urls)],
    addresses: [...new Set(addresses)],
    dates: [...new Set(dates)],
  };
}

// Maps a phone number to a tel: URI, a US-style display, and a reverse-ask link
function phoneActions(raw) {
  const digits = raw.replace(/[^\d]/g, '');
  const tel = 'tel:' + digits;
  const display = digits.length === 10
    ? `(${digits.slice(0,3)}) ${digits.slice(3,6)}-${digits.slice(6)}`
    : raw;
  return { tel, display, digits };
}

function addressActions(raw) {
  const q = encodeURIComponent(raw);
  return {
    maps: `https://maps.apple.com/?q=${q}`,   // iOS + macOS opens Maps.app
    google: `https://www.google.com/maps/search/?api=1&query=${q}`,
    display: raw.length > 60 ? raw.slice(0, 57) + '…' : raw,
  };
}

// ── Fast rule-based pre-classifier ─────────────────────────────────────────
// Runs before any LLM call. If it produces high-confidence output, we skip
// the network trip entirely. Also serves as the offline fallback.
function ruleClassify(text, entities, projects) {
  const t = text.toLowerCase();

  // Alfredo-action: user wants the assistant to DO something about this.
  // Trigger patterns: "alfredo", leading "a " (vocative), "help me", "find me",
  // "can you", "please", "where can i", "look up".
  const alfredoRe = /^(alfredo[,\s]|a\s|help me |find me |can you |please |where can i |look up |look into |search for |research |get me |order |book )/i;
  const pleadingRe = /(please|pretty please|halp|hotshot|good boy|bc i|sierra|got shit done)/i;
  if (alfredoRe.test(text) || (pleadingRe.test(t) && /\?|help|find|where|need/i.test(t))) {
    return {
      type: 'alfredo-action',
      reason: 'user is asking alfredo to do something',
      confidence: 0.88,
    };
  }

  // Fuzzy project match — does the note mention a project name / slug word?
  const projectMatch = projects.find(p => {
    const word = p.name.split('.')[0].toLowerCase();
    return word.length >= 4 && t.includes(word);
  });
  if (projectMatch) {
    return {
      type: 'project-task',
      target: projectMatch.name,
      reason: `mentions "${projectMatch.name.split('.')[0].toLowerCase()}"`,
      confidence: 0.82,
    };
  }

  // Calendar-ish phrases need approval
  const calWords = /(dinner|lunch|breakfast|brunch|flight|reservation|appt|appointment|meeting w\/|coffee w\/|drinks w\/|dentist|doctor)/i;
  if (calWords.test(t) || (entities.dates.length && /at\s+\d/.test(t))) {
    // t&s default when partner-ish words appear
    const tsWords = /(sierra|we |us |our |together|dinner w\/|brunch w\/|flight)/i;
    const workWords = /(renata|david|priya|omnidian|qaqc|forecast|standup|sync|1:1)/i;
    const calendar = tsWords.test(t) ? 'ts' : workWords.test(t) ? 'work' : 'personal';
    return {
      type: 'event-suggestion',
      calendar,
      reason: 'looks like an event — needs approval before write',
      confidence: 0.7,
    };
  }

  // Action-verb → todo
  const verbMatch = /\b(call|email|text|ping|ask|book|buy|pick up|drop off|schedule|make|pay|check|order|cancel|reply|follow up|reach out)\b/i;
  if (verbMatch.test(t)) {
    return {
      type: 'todo',
      reason: 'action verb at the front',
      confidence: 0.78,
    };
  }

  // "need to / have to / remember to"
  if (/\b(need to|have to|remember to|gotta|should)\b/i.test(t)) {
    return { type: 'todo', reason: '"need/have/remember to"', confidence: 0.72 };
  }

  // Bare phone/address/url with no verb → note (user can reclassify)
  if (entities.phones.length || entities.addresses.length || entities.urls.length) {
    return { type: 'note', reason: 'contains contact/location info', confidence: 0.6 };
  }

  return { type: 'note', reason: 'no clear action signal', confidence: 0.4 };
}

// ── LLM classifier (upgrades the rule result when confidence is low) ──────
async function llmClassify(text, entities, projects) {
  if (!window.claude || !window.claude.complete) return null;
  const projectList = projects.map(p => p.name).join(', ');
  const sys = [
    'You classify scratchpad notes. Return ONLY a JSON object, no prose, no markdown fences.',
    'Schema: {"type":"todo|task|project-task|event-suggestion|note|ignore","target":"<project name or null>","reason":"<one short sentence>","calendar":"work|personal|ts|null","confidence":0.0-1.0}',
    'Rules:',
    '- project-task: note mentions or clearly relates to one of these active projects: ' + projectList,
    '- event-suggestion: note mentions a scheduled thing (flight/dinner/appt/meeting/reservation). Must set calendar. Never write to calendar without user approval.',
    '- todo: an action the user needs to do, not yet scheduled.',
    '- task: a generic work item, when you can\'t tell if it belongs to a specific project.',
    '- note: reference info, contact, address, reminder to think about something.',
    '- ignore: obvious noise.',
    'Calendar targets: work = Omnidian; personal = Todd (solo); ts = Todd & Sierra shared (use for flights, reservations, date-night, mutual friends).',
    `Entities detected: phones=${entities.phones.length}, addresses=${entities.addresses.length}, urls=${entities.urls.length}, dates=${entities.dates.join(',') || 'none'}`,
    `Note: ${text}`,
  ].join('\n');
  try {
    const reply = await window.claude.complete({ messages: [{ role: 'user', content: sys }] });
    const match = reply.match(/\{[\s\S]*\}/);
    if (!match) return null;
    const parsed = JSON.parse(match[0]);
    if (!parsed.type) return null;
    return parsed;
  } catch {
    return null;
  }
}

// Combined classifier — rule first, upgrade with LLM if confidence < 0.8.
async function classifyNote(text, entities, projects) {
  const ruleResult = ruleClassify(text, entities, projects);
  if (ruleResult.confidence >= 0.8) return ruleResult;
  const llm = await llmClassify(text, entities, projects);
  if (llm) return llm;
  return ruleResult;
}

// ── Presentation helpers ────────────────────────────────────────────────────
const CLASS_BADGE = {
  'todo': { label: 'TODO', color: 'var(--accent)' },
  'task': { label: 'TASK', color: 'var(--accent)' },
  'project-task': { label: 'PROJ·TASK', color: 'var(--good)' },
  'event-suggestion': { label: 'CAL·PROPOSE', color: 'var(--warn)' },
  'alfredo-action': { label: 'α·ACTION', color: 'var(--accent)' },
  'note': { label: 'NOTE', color: 'var(--text-dim)' },
  'ignore': { label: 'IGNORE', color: 'var(--muted-dim)' },
};

const CAL_LABEL = { work: 'OMNIDIAN', personal: 'TODD', ts: 'T & S' };

// Items go to 'acted' state after classification + routing.
// After GREY_AFTER_MS they grey out (not strikethrough) but stay visible.
// After EXPIRE_AFTER_MS they drop from the pad entirely.
const GREY_AFTER_MS = 4 * 60 * 60 * 1000;    // 4h
const EXPIRE_AFTER_MS = 24 * 60 * 60 * 1000; // 24h

function ageState(item, now) {
  if (item.state !== 'acted') return item.state;
  const age = now - (item.actedAt || item.addedAt);
  if (age > EXPIRE_AFTER_MS) return 'expired';
  if (age > GREY_AFTER_MS) return 'stale';
  return 'acted';
}

// ── Proactive suggestions ──────────────────────────────────────────────────
// Alfredo periodically reviews context (projects, calendar, scratch) and
// proposes things the user hasn't thought of. Each suggestion is a synthetic
// scratch item with source='alfredo' and pre-baked classification — so the
// existing triage + approval flow handles them uniformly.

function ruleSuggestions(ctx) {
  const out = [];
  const now = new Date();
  const projects = ctx.projects || [];
  const calendar = ctx.calendar || [];
  const scratch = ctx.scratch || [];

  // 1. Active trip projects → prep suggestions
  const trip = projects.find(p => /trip|travel|vacation|eurotrip/i.test(p.name) && p.state === 'ACTIVE');
  if (trip) {
    out.push({
      text: 'Walking shoes for ' + trip.name.toLowerCase() + '? Amateur Athlete in Bethlehem has a good selection. Stop on your way to dinner Fri.',
      classification: {
        type: 'event-suggestion',
        calendar: 'ts',
        reason: 'unresolved packing task on ' + trip.name + ' + you have dinner Fri',
        confidence: 0.72,
      },
      appliedTo: 'CAL·T & S · awaiting approval',
    });
    out.push({
      text: 'EU sim card — Airalo eSIM is cheapest. Order a week before you fly.',
      classification: { type: 'project-task', target: trip.name, reason: 'recurring pre-trip task', confidence: 0.8 },
      appliedTo: trip.name,
    });
  }

  // 2. Stalled projects → nudge
  const stalled = projects.find(p => p.state === 'STALLED');
  if (stalled) {
    out.push({
      text: 'Pick a ' + stalled.name.toLowerCase().split('.')[1] + ' option today. You\'ve been picking for 11 days. 15 min, done.',
      classification: { type: 'todo', reason: stalled.name + ' is stalled', confidence: 0.85 },
      appliedTo: 'TODAY · TODOs',
    });
  }

  // 3. Calendar gaps → suggest lunch, prep, etc.
  const today = calendar.filter(c => !c.day);
  const hasLunchBlock = today.some(c => /lunch/i.test(c.title));
  if (!hasLunchBlock && now.getHours() < 12) {
    out.push({
      text: 'No lunch block on the calendar. Want to protect 12:30–1? You\'ve got a 60-min hole.',
      classification: { type: 'event-suggestion', calendar: 'personal', reason: 'calendar has a 12:30 gap', confidence: 0.65 },
      appliedTo: 'CAL·TODD · awaiting approval',
    });
  }

  // 4. Meeting tomorrow that needs prep
  const tomorrowEvents = calendar.filter(c => c.day === 1);
  const workTom = tomorrowEvents.find(c => c.tag === 'WORK');
  if (workTom && now.getHours() >= 20) {
    out.push({
      text: 'Review ' + workTom.title.toLowerCase() + ' notes tonight — 10 min. Tomorrow-you will thank you.',
      classification: { type: 'todo', reason: workTom.title + ' on tomorrow\'s cal', confidence: 0.7 },
      appliedTo: 'TODAY · TODOs',
    });
  }

  // 5. Hydration / small life nudges
  const hasWaterNote = scratch.some(s => /water|hydrat/i.test(s.text || ''));
  if (!hasWaterNote && now.getHours() > 10 && now.getHours() < 16) {
    out.push({
      text: 'Drink a glass of water. You haven\'t logged one today.',
      classification: { type: 'note', reason: 'routine', confidence: 0.4 },
      appliedTo: 'kept as note',
    });
  }

  return out;
}

async function llmSuggestions(ctx) {
  if (!window.claude || !window.claude.complete) return null;
  const summary = [
    'You are alfredo, proposing proactive suggestions in a dry, minimal tone.',
    'Current context:',
    '- Time: ' + new Date().toLocaleString(),
    '- Projects: ' + (ctx.projects || []).map(p => `${p.name}(${p.state}) · next: ${p.next}`).join(' · '),
    '- Today: ' + (ctx.calendar || []).filter(c => !c.day).map(c => `${c.time} ${c.title}`).join(' · '),
    '- Recent notes: ' + (ctx.scratch || []).slice(-4).map(s => s.text).filter(Boolean).join(' | '),
    '',
    'Return a JSON ARRAY of 1–3 suggestions. Each object:',
    '{"text":"<one-sentence suggestion, max 120 chars>","type":"todo|task|project-task|event-suggestion|note","target":"<project name or null>","calendar":"work|personal|ts|null","reason":"<one short sentence>","confidence":0.0-1.0}',
    'RETURN ONLY the JSON array. No prose, no markdown fences.',
  ].join('\n');
  try {
    const reply = await window.claude.complete({ messages: [{ role: 'user', content: summary }] });
    const match = reply.match(/\[[\s\S]*\]/);
    if (!match) return null;
    const arr = JSON.parse(match[0]);
    if (!Array.isArray(arr)) return null;
    // Convert to scratch-item shape
    return arr.map(s => ({
      text: s.text,
      classification: { type: s.type, target: s.target || undefined, calendar: s.calendar || undefined, reason: s.reason, confidence: s.confidence },
      appliedTo: (
        s.type === 'event-suggestion' ? `CAL·${(CAL_LABEL[s.calendar] || '?').toUpperCase()} · awaiting approval`
        : s.type === 'project-task' ? (s.target || 'PROJECTS')
        : s.type === 'todo' || s.type === 'task' ? 'TODAY · TODOs'
        : 'kept as note'
      ),
    }));
  } catch {
    return null;
  }
}

// Combined generator — try LLM, fall back to rules. De-dupes against existing scratch text.
async function generateSuggestions(ctx) {
  let list = await llmSuggestions(ctx);
  if (!list || !list.length) list = ruleSuggestions(ctx);
  const existing = new Set((ctx.scratch || []).map(s => (s.text || '').toLowerCase()));
  return list
    .filter(s => s.text && !existing.has(s.text.toLowerCase()))
    .slice(0, 3);
}

Object.assign(window, {
  detectEntities,
  phoneActions,
  addressActions,
  classifyNote,
  ruleClassify,
  generateSuggestions,
  parsePriority,
  suggestPriorityLLM,
  CLASS_BADGE,
  CAL_LABEL,
  PRIORITY_META,
  P0_CAP,
  ageState,
  GREY_AFTER_MS,
  EXPIRE_AFTER_MS,
});
