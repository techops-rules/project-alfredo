// Reusable widget chrome + atoms.
// Every widget is a "pane" with a TITLE.BAR and a body.
// Chrome intensity scales from 0 (clean) to 2 (full HUD).

const { useState, useEffect, useRef, useMemo } = React;

// ─────────────────────────────────────────────────────────────────────────────
// PANE — the core widget container
// ─────────────────────────────────────────────────────────────────────────────
// CollapseContext lets any Pane collapse itself using its title as a key.
// App provides { collapsed: {[title]: bool}, toggle: (title) => void }.
const CollapseContext = React.createContext(null);

function Pane({ title, sub, accent, chrome = 1, children, style, onClick, footer, dense, className, collapsible = true }) {
  const ascii = chrome >= 2;
  const showCorners = chrome >= 1;
  const padBody = dense ? '6px 10px 8px' : '10px 12px 12px';
  const ctx = React.useContext(CollapseContext);
  const isCollapsed = collapsible && ctx && ctx.collapsed[title];

  const onTitleClick = (e) => {
    if (!collapsible || !ctx) return;
    e.stopPropagation();
    ctx.toggle(title);
  };

  return (
    <div className={`pane ${className || ''} ${isCollapsed ? 'collapsed' : ''}`} style={style} onClick={onClick}>
      {showCorners && !isCollapsed && (
        <>
          <span className="pane-corner pane-corner-tl">{ascii ? '┌─' : '╴'}</span>
          <span className="pane-corner pane-corner-tr">{ascii ? '─┐' : '╶'}</span>
        </>
      )}

      <div className={`pane-title ${collapsible && ctx ? 'collapsible' : ''}`} onClick={onTitleClick}>
        <span className="pane-title-dot" style={accent ? { background: accent } : null} />
        <span className="pane-title-name">{title}</span>
        {collapsible && ctx && <span className="pane-title-caret">▼</span>}
        {sub && <span className="pane-title-sub">{sub}</span>}
      </div>

      {!isCollapsed && (
        <div className="pane-body" style={{ padding: padBody }}>
          {children}
        </div>
      )}

      {footer && !isCollapsed && <div className="pane-footer">{footer}</div>}

      {showCorners && !isCollapsed && (
        <>
          <span className="pane-corner pane-corner-bl">{ascii ? '└─' : '╴'}</span>
          <span className="pane-corner pane-corner-br">{ascii ? '─┘' : '╶'}</span>
        </>
      )}
    </div>
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// CONFIDENCE — three variants
// ─────────────────────────────────────────────────────────────────────────────
function Conf({ value, variant = 'dot' }) {
  if (value == null) return null;
  if (variant === 'dot') {
    return (
      <span className="conf-dot-wrap" title={`confidence ${Math.round(value*100)}%`}>
        <span className="conf-dot" style={{ background: confColor(value), opacity: 0.4 + value * 0.6 }} />
      </span>
    );
  }
  if (variant === 'pct') {
    return <span className="conf-pct">{Math.round(value*100)}%</span>;
  }
  if (variant === 'fade') {
    return null; // applied via opacity on parent
  }
  return null;
}

const fadeOpacity = (variant, value) => variant === 'fade' && value != null ? (0.45 + value * 0.55) : 1;

// ─────────────────────────────────────────────────────────────────────────────
// DAILY BRIEF
// ─────────────────────────────────────────────────────────────────────────────
function DailyBrief({ chrome, confVariant, onFocus }) {
  return (
    <Pane title="DAILY.BRIEF" sub={`COMPILED ${DAILY_BRIEF.generatedAt}`} chrome={chrome}>
      <div className="brief-headline"><RotatingHeadline /></div>
      <div className="brief-mood">{DAILY_BRIEF.mood}</div>
      <div className="brief-list">
        {DAILY_BRIEF.items.map((it, i) => (
          <div key={i} className="brief-item" style={{ opacity: fadeOpacity(confVariant, it.confidence) }} onClick={() => onFocus && onFocus(it)}>
            <div className="brief-rank">0{it.rank}</div>
            <div className="brief-body">
              <div className="brief-label">
                <span className={`tag tag-${it.tag.toLowerCase()}`}>{it.tag}</span>
                <span>{it.label}</span>
                <Conf value={it.confidence} variant={confVariant} />
              </div>
              <div className="brief-why">› {it.why}</div>
              <div className="brief-source">{it.source}</div>
            </div>
          </div>
        ))}
      </div>
      <div className="brief-swept">
        <div className="brief-swept-head">SWEPT · {DAILY_BRIEF.swept.length} ITEMS · NOT SHOWN</div>
        <div className="brief-swept-list">
          {DAILY_BRIEF.swept.map((s, i) => (
            <span key={i} className="swept-chip">{s.label}</span>
          ))}
        </div>
      </div>
    </Pane>
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// CALENDAR
// ─────────────────────────────────────────────────────────────────────────────
function CalendarPane({ chrome, dense, calendar }) {
  const overrides = calendar?.overrides || {};
  const onOpen = calendar?.onOpenEvent;
  const [showHidden, setShowHidden] = useState(false);

  const renderRow = (e, idx, isTomorrow = false) => {
    const key = 'e::' + CALENDAR.indexOf(e);
    const o = overrides[key] || {};
    if (o.deleted) return null;
    if (o.hidden && !showHidden) return null;
    const merged = { ...e, ...(o.edits || {}) };
    const tags = o.tags || [merged.tag];
    return (
      <div
        key={key}
        className={`cal-row ${merged.soon ? 'cal-soon' : ''} ${merged.soft ? 'cal-soft' : ''} ${merged.hard ? 'cal-hard' : ''} ${o.hidden ? 'cal-hidden' : ''} ${isTomorrow ? 'cal-tomorrow' : ''}`}
        style={{ cursor: onOpen ? 'pointer' : 'default' }}
        onClick={() => onOpen && onOpen(key)}
      >
        <div className="cal-time">{isTomorrow ? merged.time.replace('Sat ', '') : merged.time}</div>
        <div className="cal-rail">
          {merged.soon ? <span className="cal-marker">▶</span> : merged.hard ? <span className="cal-marker cal-marker-hard">!</span> : <span className={`cal-marker ${isTomorrow ? '' : 'cal-marker-dot'}`}>{isTomorrow ? '·' : '•'}</span>}
        </div>
        <div className="cal-body">
          <div className="cal-title">{merged.title}{o.hidden && ' · hidden'}</div>
          <div className="cal-meta">{merged.where} · {merged.dur}</div>
        </div>
        {tags.slice(0, 2).map(t => t && <span key={t} className={`tag tag-${t.toLowerCase()} tag-mini`}>{t}</span>)}
      </div>
    );
  };

  const today = CALENDAR.filter(c => !c.day);
  const tomorrow = CALENDAR.filter(c => c.day === 1);
  const hiddenCount = Object.values(overrides).filter(o => o.hidden && !o.deleted).length;

  return (
    <Pane title="CALENDAR" sub="TODAY · +48H" chrome={chrome} dense={dense}>
      <div className="cal-head">FRI APR 17</div>
      {today.map((e, i) => renderRow(e, i, false))}
      <div className="cal-head cal-head-tomorrow">SAT APR 18</div>
      {tomorrow.map((e, i) => renderRow(e, i, true))}
      {hiddenCount > 0 && (
        <button className="cal-show-hidden" onClick={() => setShowHidden(!showHidden)}>
          {showHidden ? 'hide ' : 'show '}{hiddenCount} hidden
        </button>
      )}
    </Pane>
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// INBOX TRIAGE
// ─────────────────────────────────────────────────────────────────────────────
function InboxPane({ chrome, confVariant, dense, onOpen, sentMails = [] }) {
  const [filter, setFilter] = useState('ALL');
  const counts = INBOX.reduce((a, i) => ({ ...a, [i.classified]: (a[i.classified] || 0) + 1 }), {});
  const fmtAge = (ms) => {
    const m = Math.floor((Date.now() - ms) / 60000);
    if (m < 1) return 'now';
    if (m < 60) return m + 'm';
    const h = Math.floor(m / 60);
    if (h < 24) return h + 'h';
    return Math.floor(h / 24) + 'd';
  };
  const inSent = filter === 'SENT';
  const items = inSent
    ? [...sentMails].reverse()   // newest first
    : filter === 'ALL' ? INBOX : INBOX.filter(i => i.classified === filter);
  const subLabel = inSent
    ? `${sentMails.length} SENT · VIA ALFREDO`
    : `${INBOX.length} CLASSIFIED · ${counts.ESCALATE || 0} ESC`;
  return (
    <Pane title="INBOX.TRIAGE" sub={subLabel} chrome={chrome} dense={dense}>
      <div className="inbox-filter">
        {['ALL', 'ESCALATE', 'FYI', 'IGNORE', 'SENT'].map(f => {
          const c = f === 'SENT' ? sentMails.length : counts[f];
          return (
            <button key={f} className={`inbox-filter-btn ${filter === f ? 'active' : ''} ${f === 'SENT' ? 'sent' : ''}`} onClick={() => setFilter(f)}>
              {f}{f !== 'ALL' && <span className="inbox-filter-count">·{c || 0}</span>}
            </button>
          );
        })}
      </div>
      <div className="inbox-list">
        {inSent && items.length === 0 && (
          <div style={{ fontSize: 10, color: 'var(--muted)', fontStyle: 'italic', padding: '8px 0' }}>
            no sent mail yet · reply to something to populate
          </div>
        )}
        {items.map((it, i) => {
          if (inSent) {
            return (
              <div
                key={it.id || i}
                className="inbox-row sent-row"
                style={{ cursor: 'pointer' }}
                onClick={() => onOpen && onOpen({
                  ...it, __sent: true,
                  from: it.to, email: it.toEmail,
                  body: it.body, snippet: it.body?.slice(0, 100),
                })}
              >
                <span className="inbox-class inbox-class-sent">✓</span>
                <div className="inbox-body">
                  <div className="inbox-line1">
                    <span className="inbox-from">To: {it.to}</span>
                    <span className="inbox-age">{fmtAge(it.sentAt)}</span>
                  </div>
                  <div className="inbox-subject">{it.subject}</div>
                  <div className="inbox-snippet">{(it.body || '').split('\n')[0].slice(0, 90)}</div>
                </div>
              </div>
            );
          }
          return (
            <div
              key={i}
              className="inbox-row"
              style={{ opacity: fadeOpacity(confVariant, it.confidence), cursor: 'pointer' }}
              onClick={() => onOpen && onOpen(it)}
            >
              <span className={`inbox-class inbox-class-${it.classified.toLowerCase()}`}>{it.classified[0]}</span>
              <div className="inbox-body">
                <div className="inbox-line1">
                  <span className="inbox-from">{it.from}</span>
                  <Conf value={it.confidence} variant={confVariant} />
                  <span className="inbox-age">{it.age}</span>
                </div>
                <div className="inbox-subject">{it.subject}</div>
                <div className="inbox-snippet">{it.snippet}</div>
              </div>
            </div>
          );
        })}
      </div>
    </Pane>
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// PROJECTS
// ─────────────────────────────────────────────────────────────────────────────
function ProjectsPane({ chrome, dense, projects }) {
  // Fallback for surfaces that don't pass state (uses static PROJECTS seed)
  const data = projects?.data || { active: PROJECTS.map(p => ({ ...p, id: 'p-' + p.name, subtasks: [] })), archive: [], trash: [] };
  const filter = projects?.filter || 'active';
  const [newProjName, setNewProjName] = useState('');
  const [adding, setAdding] = useState(false);
  const list = data[filter] || [];
  return (
    <Pane
      title="PROJECTS"
      sub={`${data.active.length} · ${data.archive.length} ARCH · ${data.trash.length} TRASH`}
      chrome={chrome}
      dense={dense}
    >
      <div className="proj-filter">
        {['active', 'archive', 'trash'].map(f => (
          <button
            key={f}
            className={`proj-filter-btn ${filter === f ? 'active' : ''}`}
            onClick={() => projects?.setFilter(f)}
          >{f.toUpperCase()}<span className="proj-filter-count">·{data[f].length}</span></button>
        ))}
      </div>
      {list.length === 0 && (
        <div style={{ fontSize: 10, color: 'var(--muted)', fontStyle: 'italic', padding: '8px 0' }}>
          {filter === 'trash' ? 'trash is empty' : filter === 'archive' ? 'nothing archived' : 'no active projects — add one below'}
        </div>
      )}
      {list.map((p) => (
        <window.SwipeRow
          key={p.id}
          onSwipeLeft={() => projects?.onSwipeLeft(p.id)}
          onSwipeRight={filter === 'active' ? () => projects?.onSwipeRight(p.id) : null}
          leftLabel="ARCHIVE"
          rightLabel={filter === 'trash' ? 'DELETE' : 'TRASH'}
        >
          <div className="proj-row proj-swipe" onClick={() => projects?.onOpen(p.id)}>
            <div className="proj-head">
              <span className={`proj-health proj-health-${p.health}`} />
              <span className="proj-name">{p.name}</span>
              <span className={`proj-state proj-state-${(p.state || 'active').split('.')[0].toLowerCase()}`}>{p.state}</span>
            </div>
            <div className="proj-last">last › {p.last}</div>
            <div className="proj-next">next › {p.next}</div>
            <div className="proj-meta">
              <span>{(p.subtasks || []).length} subtasks</span>
              {p.blockers > 0 && <span className="proj-blockers">{p.blockers} blocked</span>}
              <span className="proj-owner">{p.owner}</span>
              {filter === 'trash' && (
                <button
                  onClick={(e) => { e.stopPropagation(); projects?.onRestore(p.id); }}
                  className="proj-restore"
                >RESTORE</button>
              )}
            </div>
          </div>
        </window.SwipeRow>
      ))}
      {filter === 'active' && (
        adding ? (
          <div className="proj-add-row">
            <input
              autoFocus
              className="proj-add-input"
              value={newProjName}
              onChange={e => setNewProjName(e.target.value)}
              onKeyDown={e => {
                if (e.key === 'Enter' && newProjName.trim()) {
                  projects?.onAdd(newProjName.trim());
                  setNewProjName('');
                  setAdding(false);
                } else if (e.key === 'Escape') {
                  setNewProjName(''); setAdding(false);
                }
              }}
              onBlur={() => {
                if (newProjName.trim()) { projects?.onAdd(newProjName.trim()); setNewProjName(''); }
                setAdding(false);
              }}
              placeholder="PROJECT.NAME"
            />
          </div>
        ) : (
          <button className="proj-add-btn" onClick={() => setAdding(true)}>+ NEW PROJECT</button>
        )
      )}
    </Pane>
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// SCRATCH PAD — tap blank dot to add
// ─────────────────────────────────────────────────────────────────────────────
// ScratchPane is now a triage landing pad.
// Items are shared app state (passed in as `items` + mutators) so kiosk, macOS,
// and iOS all see the same queue.
function ScratchPane({ chrome, dense, items, onAdd, onInspect }) {
  const [adding, setAdding] = useState(false);
  const [draft, setDraft] = useState('');
  const inputRef = useRef(null);
  // tick every 60s so age-based greying updates without interaction
  const [, setTick] = useState(0);
  useEffect(() => {
    const id = setInterval(() => setTick(t => t + 1), 60000);
    return () => clearInterval(id);
  }, []);

  useEffect(() => {
    if (adding && inputRef.current) inputRef.current.focus();
  }, [adding]);

  const commit = () => {
    const text = draft.trim();
    if (text) onAdd(text);
    setDraft('');
    setAdding(false);
  };

  const now = Date.now();
  const visible = items.filter(it => ageState(it, now) !== 'expired');

  return (
    <Pane title="SCRATCH.PAD" sub="TRIAGE · TAP · TO · ADD" chrome={chrome} dense={dense}>
      <div className="scratch-list">
        {visible.map((it) => {
          const age = ageState(it, now);
          const cls = CLASS_BADGE[it.classification?.type] || null;
          const badgeText = it.state === 'triaging' ? 'TRIAGING…' : cls?.label;
          const badgeColor = it.state === 'triaging' ? 'var(--muted)' : cls?.color;
          return (
            <div
              key={it.id}
              className={`scratch-row ${age === 'stale' ? 'stale' : ''} ${it.source === 'alfredo' ? 'from-alfredo' : ''} ${it.approved ? 'approved' : ''}`}
              onClick={() => onInspect(it)}
            >
              <span className={`scratch-dot ${age === 'acted' || age === 'stale' ? 'scratch-dot-active' : ''}`}>
                {age === 'acted' ? '◉' : age === 'stale' ? '◍' : '○'}
              </span>
              <div className="scratch-text-row">
                <div style={{ display: 'flex', alignItems: 'flex-start', gap: 6 }}>
                  {it.priority && (() => {
                    const meta = PRIORITY_META[it.priority];
                    const isClaude = it.prioritySource === 'claude';
                    return (
                      <span
                        className={`priority-chip mini ${isClaude ? 'claude' : ''}`}
                        style={{
                          color: isClaude ? 'var(--muted)' : meta.color,
                          borderColor: isClaude ? 'var(--muted-dim)' : meta.color,
                          boxShadow: isClaude ? 'none' : `0 0 6px ${meta.glow}`,
                        }}
                        title={`${meta.desc}${isClaude ? ' · α suggested' : ''}`}
                      >{it.priority}</span>
                    );
                  })()}
                  <span className="scratch-text">{it.text}</span>
                </div>
                {(badgeText || it.appliedTo) && (
                  <div className="scratch-meta">
                    {badgeText && (
                      <span className={`scratch-badge ${it.state === 'triaging' ? 'triaging' : ''}`} style={{ color: badgeColor }}>
                        {badgeText}
                      </span>
                    )}
                    {it.appliedTo && <span className="scratch-applied">→ {it.appliedTo}</span>}
                  </div>
                )}
              </div>
            </div>
          );
        })}
        {adding ? (
          <div className="scratch-row">
            <span className="scratch-dot scratch-dot-active">▸</span>
            <input
              ref={inputRef}
              className="scratch-input"
              value={draft}
              onChange={e => setDraft(e.target.value)}
              onBlur={commit}
              onKeyDown={e => {
                if (e.key === 'Enter') commit();
                if (e.key === 'Escape') { setDraft(''); setAdding(false); }
              }}
              placeholder="drop anything — i'll sort it"
            />
          </div>
        ) : (
          <div className="scratch-row scratch-blank" onClick={() => setAdding(true)}>
            <span className="scratch-dot scratch-dot-empty">◌</span>
            <span className="scratch-text scratch-text-empty">tap to add · i'll triage</span>
          </div>
        )}
        <div className="scratch-row scratch-blank scratch-blank-faint" onClick={() => setAdding(true)}>
          <span className="scratch-dot scratch-dot-empty">◌</span>
        </div>
        <div className="scratch-row scratch-blank scratch-blank-faintest" onClick={() => setAdding(true)}>
          <span className="scratch-dot scratch-dot-empty">◌</span>
        </div>
      </div>
    </Pane>
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// PULSE (next meeting)
// ─────────────────────────────────────────────────────────────────────────────
function PulsePane({ chrome, confVariant, dense }) {
  return (
    <Pane title="NEXT.PULSE" sub={`T-${PULSE.inMinutes}M`} chrome={chrome} dense={dense} accent="var(--accent)">
      <div className="pulse-head">
        <div className="pulse-meeting">{PULSE.meeting}</div>
        <div className="pulse-time">
          {PULSE.startsAt}
          <Conf value={PULSE.confidence} variant={confVariant} />
        </div>
      </div>
      <div className="pulse-section">
        <div className="pulse-label">LAST · TIME</div>
        <div className="pulse-text">{PULSE.lastDiscussion}</div>
      </div>
      <div className="pulse-section">
        <div className="pulse-label">OPEN · QS</div>
        {PULSE.openQuestions.map((q, i) => (
          <div key={i} className="pulse-q">› {q}</div>
        ))}
      </div>
      <div className="pulse-section">
        <div className="pulse-label">PREP</div>
        {PULSE.prep.map((p, i) => (
          <div key={i} className="pulse-prep">▢ {p}</div>
        ))}
      </div>
    </Pane>
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// CLAUDE.TTY — interactive
// ─────────────────────────────────────────────────────────────────────────────
function TTYPane({ chrome, dense, expanded }) {
  const greeting = useMemo(() => TTY_GREETINGS[Math.floor(Math.random() * TTY_GREETINGS.length)], []);
  const [lines, setLines] = useState([
    { who: 'sys', text: 'alfredo v0.4.1 · wake-word "alfredo" · ready' },
    { who: 'a', text: greeting },
  ]);
  const [draft, setDraft] = useState('');
  const [busy, setBusy] = useState(false);
  const scrollRef = useRef(null);
  // Re-read key on every send so TWEAKS edits take effect immediately
  const hasKey = typeof window !== 'undefined' && !!localStorage.getItem('alfredo:anthropic_key');

  useEffect(() => {
    if (scrollRef.current) scrollRef.current.scrollTop = scrollRef.current.scrollHeight;
  }, [lines, busy]);

  const SYS_PROMPT = [
    'You are alfredo, Todd\'s personal external-brain assistant.',
    'PERSONA: deadpan, dry, mildly mean (Monday persona). Roast lightly but be uncannily accurate.',
    '',
    'BIAS FOR ACTION — this is the core rule:',
    '  • Every response must end with a concrete next move. Name the thing, name the time, name the person when relevant.',
    '  • NO general advice. NO "you could try…", "consider…", "maybe…", "it depends…".',
    '  • If the user asks a question, give the answer + the action that follows from it.',
    '  • If you don\'t know, say exactly what to check / who to ask, not "it depends".',
    '  • Prefer "draft the email to X now" over "you should probably email X".',
    '',
    'FORMAT: 1–3 short lines, lowercase preferred, no emoji, no markdown.',
    '',
    'CONTEXT (today, Fri Apr 17 2026 08:42):',
    '  three priorities — (1) ship Q2 forecast to Renata by EOD, (2) 10am QAQC sync, owe agenda, (3) pick up Mira at 15:15.',
    '  inbox: Renata pinged twice for forecast, David says batch-41 fixture didn\'t help, Sam confirmed dinner 8pm Quince.',
    '  projects: QAQC.PROCESS yellow, Q2.FORECAST red due today, ALFREDO.SELF green, HOUSE.ROOF stalled 11 days. EUROTRIP in 14 days.',
    '  user slept 5h12m.',
  ].join('\n');

  const send = async () => {
    const q = draft.trim();
    if (!q) return;
    setLines(l => [...l, { who: 'u', text: q }]);
    setDraft('');
    setBusy(true);
    const apiKey = localStorage.getItem('alfredo:anthropic_key');

    // Reserve a blank assistant line that we'll stream into.
    setLines(l => [...l, { who: 'a', text: '' }]);
    const appendDelta = (chunk) => {
      setLines(l => {
        const copy = [...l];
        const last = copy[copy.length - 1];
        copy[copy.length - 1] = { ...last, text: last.text + chunk };
        return copy;
      });
    };

    try {
      if (apiKey && window.streamClaude) {
        await window.streamClaude({
          apiKey,
          system: SYS_PROMPT,
          userText: q,
          onDelta: appendDelta,
          model: 'claude-sonnet-4-6',
        });
      } else {
        // Fallback: one-shot non-streaming
        const reply = await window.claude.complete({
          messages: [{ role: 'user', content: SYS_PROMPT + '\n\nUser asks: ' + q }]
        });
        appendDelta(reply.trim());
      }
    } catch (e) {
      appendDelta('(' + (e.message || 'error') + ')');
    } finally {
      setBusy(false);
    }
  };

  const statusLabel = busy
    ? 'THINKING…'
    : hasKey ? '● LIVE · sonnet' : '● STUB · no key';

  return (
    <Pane title="CLAUDE.TTY" sub={statusLabel} chrome={chrome} dense={dense}>
      <div className={`tty-scroll ${expanded ? 'tty-scroll-tall' : ''}`} ref={scrollRef}>
        {lines.map((l, i) => {
          const isStreaming = busy && i === lines.length - 1 && l.who === 'a';
          return (
            <div key={i} className={`tty-line tty-${l.who}`}>
              <span className="tty-prompt">
                {l.who === 'sys' ? '##' : l.who === 'u' ? '›' : 'α'}
              </span>
              <span className="tty-text">{l.text}{isStreaming ? '▌' : ''}</span>
              {!isStreaming && l.text && l.who !== 'sys' && window.CopyButton && <window.CopyButton text={l.text} />}
            </div>
          );
        })}
      </div>
      <div className="tty-input-row">
        <span className="tty-prompt">›</span>
        <input
          className="tty-input"
          value={draft}
          onChange={e => setDraft(e.target.value)}
          onKeyDown={e => { if (e.key === 'Enter' && !busy) send(); }}
          placeholder={busy ? '…' : hasKey ? 'ask alfredo' : 'set api key in TWEAKS to go live'}
          disabled={busy}
        />
      </div>
    </Pane>
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// STATUS BAR (top of kiosk / window)
// ─────────────────────────────────────────────────────────────────────────────
function StatusBar({ surface, chrome }) {
  const [t, setT] = useState(NOW);
  useEffect(() => {
    const i = setInterval(() => setT(new Date(NOW.getTime() + (Date.now() - mountedAt))), 1000);
    return () => clearInterval(i);
  }, []);
  const mountedAt = useMemo(() => Date.now(), []);
  const time = t.toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit', hour12: false });
  const date = t.toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric' }).toUpperCase();

  return (
    <div className="status-bar">
      <div className="status-left">
        <span className="status-logo">α</span>
        <span className="status-title">ALFREDO</span>
        <span className="status-divider">│</span>
        <span className="status-surface">{surface}</span>
      </div>
      <div className="status-center">
        <span className="status-pill"><span className="status-dot ok"/> INGEST · OK</span>
        <span className="status-pill"><span className="status-dot ok"/> 6 SOURCES</span>
        <span className="status-pill"><span className="status-dot warn"/> SLEEP · 5H12M</span>
      </div>
      <div className="status-right">
        <span className="status-date">{date}</span>
        <span className="status-time">{time}</span>
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// WEATHER.SYS — sun/moon dome arc + hourly strip + live fx
// Ported from pi-kiosk, wrapped as a React component scoped under .pane-weather
// ─────────────────────────────────────────────────────────────────────────────
const WX_LAT = 40.6023, WX_LON = -75.4714; // Allentown, PA
const WX_TZ = 'America/New_York';
const WX_PLACE = 'Allentown';
const WX_CODES = {0:'☀️',1:'🌤',2:'⛅',3:'☁️',45:'🌫',48:'🌫',51:'🌦',53:'🌦',55:'🌦',61:'🌧',63:'🌧',65:'🌧',71:'❄️',73:'❄️',75:'❄️',80:'🌦',81:'🌦',82:'⛈',95:'⛈',96:'⛈',99:'⛈'};
const WX_DESC = {0:'Clear',1:'Mostly clear',2:'Partly cloudy',3:'Overcast',45:'Fog',48:'Fog',51:'Light drizzle',53:'Drizzle',55:'Heavy drizzle',61:'Light rain',63:'Rain',65:'Heavy rain',71:'Light snow',73:'Snow',75:'Heavy snow',80:'Showers',81:'Showers',82:'Heavy showers',95:'Thunderstorm',96:'Thunderstorm',99:'Thunderstorm'};

function compassFromDegrees(deg) {
  if (deg == null || Number.isNaN(Number(deg))) return '--';
  const dirs = ['N','NNE','NE','ENE','E','ESE','SE','SSE','S','SSW','SW','WSW','W','WNW','NW','NNW'];
  const n = ((Number(deg) % 360) + 360) % 360;
  return dirs[Math.round(n / 22.5) % 16];
}
function windArrowFromDegrees(deg) {
  if (deg == null || Number.isNaN(Number(deg))) return '';
  const arrows = ['↑','↗','→','↘','↓','↙','←','↖'];
  const n = ((Number(deg) % 360) + 360) % 360;
  return arrows[Math.round(n / 45) % 8];
}
function getMoonPhase() {
  const REF = Date.UTC(2000, 0, 6, 18, 14, 0);
  const SYNODIC = 29.53059;
  const daysSince = (Date.now() - REF) / 86400000;
  const age = ((daysSince % SYNODIC) + SYNODIC) % SYNODIC;
  const illum = (1 - Math.cos(2 * Math.PI * age / SYNODIC)) / 2;
  return { age, illumination: illum, isWaxing: age < SYNODIC / 2 };
}

// Canned offline fallback so the widget still looks alive without network.
function wxDemoData() {
  const today = new Date(); today.setHours(0,0,0,0);
  const sunrise0 = new Date(today); sunrise0.setHours(6, 22);
  const sunset0  = new Date(today); sunset0.setHours(19, 48);
  const sunrise1 = new Date(today); sunrise1.setDate(sunrise1.getDate()+1); sunrise1.setHours(6, 21);
  const hourlyTimes = [], hourlyTemps = [], hourlyCodes = [];
  for (let h = 0; h < 48; h++) {
    const t = new Date(today); t.setHours(h);
    hourlyTimes.push(t.toISOString());
    hourlyTemps.push(58 + Math.round(10 * Math.sin((h - 6) * Math.PI / 12)));
    hourlyCodes.push(h % 8 === 0 ? 2 : 1);
  }
  return {
    current: { temperature_2m: 64, weather_code: 2, cloud_cover: 42, wind_speed_10m: 8, wind_direction_10m: 225, precipitation: 0 },
    hourly: { time: hourlyTimes, temperature_2m: hourlyTemps, weather_code: hourlyCodes },
    daily: { sunrise: [sunrise0.toISOString(), sunrise1.toISOString()], sunset: [sunset0.toISOString()], temperature_2m_max: [72, 68], temperature_2m_min: [52, 50], weather_code: [2, 3] },
    _demo: true,
  };
}

function WeatherPane({ chrome, dense, compact }) {
  const [data, setData] = useState(null);
  const [offline, setOffline] = useState(false);
  const rootRef = useRef(null);
  const fxRef = useRef(null);
  const fxTimerRef = useRef(null);

  // Fetch live + refresh every 10 min
  useEffect(() => {
    let cancelled = false;
    const url = `https://api.open-meteo.com/v1/forecast?latitude=${WX_LAT}&longitude=${WX_LON}`
      + `&current=temperature_2m,weather_code,wind_speed_10m,wind_direction_10m,cloud_cover,precipitation`
      + `&hourly=temperature_2m,weather_code,cloud_cover,precipitation_probability`
      + `&daily=sunrise,sunset,temperature_2m_max,temperature_2m_min,weather_code`
      + `&temperature_unit=fahrenheit&wind_speed_unit=mph&timezone=${encodeURIComponent(WX_TZ)}&forecast_days=2`;
    const load = () => fetch(url).then(r => r.json()).then(d => {
      if (!cancelled) { setData(d); setOffline(false); }
    }).catch(() => {
      if (!cancelled) { setData(wxDemoData()); setOffline(true); }
    });
    load();
    const id = setInterval(load, 600000);
    // Re-render celestial position every 60s even without new fetch
    const tick = setInterval(() => setData(d => d ? { ...d } : d), 60000);
    return () => { cancelled = true; clearInterval(id); clearInterval(tick); };
  }, []);

  // Render sky cover + fx imperatively (matches kiosk behavior)
  useEffect(() => {
    if (!data || !rootRef.current) return;
    const c = data.current || {};
    const code = c.weather_code || 0;
    const cloudCover = Math.round(c.cloud_cover || 0);
    const precip = Number(c.precipitation || 0);
    const daily = data.daily || {};
    const sunrise0 = new Date(daily.sunrise?.[0]);
    const sunset0 = new Date(daily.sunset?.[0]);
    const now = new Date();
    const isDay = now >= sunrise0 && now < sunset0;

    const arcEl = rootRef.current.querySelector('.wx-arc');
    if (!arcEl) return;
    const arcW = arcEl.offsetWidth || 340;
    const arcH = arcEl.offsetHeight || 120;

    // Sky-cover clouds
    const coverEl = rootRef.current.querySelector('.wx-sky-cover');
    if (coverEl) {
      coverEl.innerHTML = '';
      const clouds = [];
      const scale = compact ? 0.78 : 1;
      const maskWidth = Math.round(((cloudCover >= 90) ? 104 : (cloudCover >= 70) ? 86 : 72) * scale);
      if (cloudCover >= 20 || [2,3,45,48,51,53,55,61,63,65,71,73,75,80,81,82,95,96,99].includes(code)) {
        clouds.push({ left: arcW * 0.5 - maskWidth * 0.5, top: 30, width: maskWidth, size: cloudCover >= 85 ? 'heavy' : 'medium' });
      }
      if (cloudCover >= 45 || code === 2 || code === 3) {
        clouds.push({ left: 44, top: 18, width: Math.round(72 * scale), size: cloudCover >= 75 ? 'medium' : 'light' });
      }
      if ((cloudCover >= 60 || code === 3) && !compact) {
        clouds.push({ left: arcW - 140, top: 38, width: 88, size: cloudCover >= 90 ? 'heavy' : 'medium' });
      }
      clouds.forEach(cl => {
        const el = document.createElement('div');
        el.className = 'wx-cloud ' + cl.size;
        el.style.left = Math.round(cl.left) + 'px';
        el.style.top = Math.round(cl.top) + 'px';
        el.style.width = Math.round(cl.width) + 'px';
        el.style.setProperty('--drift', (36 + Math.random() * 28) + 's');
        el.style.animationDelay = (-Math.random() * 12) + 's';
        coverEl.appendChild(el);
      });
    }

    // Weather FX layer (rain/snow/fog/sun-glow)
    const fxEl = fxRef.current;
    if (fxEl) {
      fxEl.innerHTML = '';
      if (fxTimerRef.current) { clearInterval(fxTimerRef.current); fxTimerRef.current = null; }
      const rainy = precip > 0.02 || [51,53,55,61,63,65,80,81,82,95,96,99].includes(code);
      const snowy = [71,73,75].includes(code);
      const foggy = [45,48].includes(code);
      const spawnRain = (n) => {
        for (let i = 0; i < n; i++) {
          const d = document.createElement('div');
          d.className = 'wx-drop';
          d.style.left = Math.random() * 100 + '%';
          d.style.height = (8 + Math.random() * 10) + 'px';
          const dur = 0.5 + Math.random() * 0.7;
          d.style.animationDuration = dur + 's';
          d.style.animationDelay = Math.random() * dur + 's';
          fxEl.appendChild(d);
        }
      };
      const spawnSnow = (n) => {
        for (let i = 0; i < n; i++) {
          const f = document.createElement('div');
          f.className = 'wx-flake';
          const sz = 2 + Math.random() * 3;
          f.style.width = sz + 'px'; f.style.height = sz + 'px';
          f.style.left = Math.random() * 100 + '%';
          const fallDur = 3 + Math.random() * 4, driftDur = 2 + Math.random() * 3;
          f.style.animationDuration = fallDur + 's,' + driftDur + 's';
          f.style.animationDelay = Math.random() * fallDur + 's,' + Math.random() * driftDur + 's';
          fxEl.appendChild(f);
        }
      };
      const spawnFog = () => {
        for (let i = 0; i < 3; i++) {
          const b = document.createElement('div');
          b.className = 'wx-fog-band';
          b.style.height = (4 + Math.random() * 6) + 'px';
          b.style.top = (20 + i * 30 + Math.random() * 10) + '%';
          b.style.animationDuration = (18 + Math.random() * 12) + 's';
          b.style.animationDelay = (-Math.random() * 10) + 's';
          fxEl.appendChild(b);
        }
      };
      if (code >= 95) spawnRain(20);
      else if (rainy && code >= 80) spawnRain(12);
      else if (snowy) spawnSnow(14);
      else if (rainy && code >= 61) spawnRain(18);
      else if (rainy && code >= 51) spawnRain(6);
      else if (foggy) spawnFog();
      else if (isDay && cloudCover < 35 && code <= 1) {
        const g = document.createElement('div'); g.className = 'wx-sun-glow'; fxEl.appendChild(g);
      }
    }
    return () => { if (fxTimerRef.current) clearInterval(fxTimerRef.current); };
  }, [data, compact]);

  if (!data) {
    return (
      <Pane title="WEATHER.SYS" sub="loading…" chrome={chrome} dense={dense} className="pane-weather wx-day">
        <div className="wx-timeline"><div className="wx-arc" /></div>
      </Pane>
    );
  }

  const c = data.current || {};
  const temp = Math.round(c.temperature_2m || 0);
  const code = c.weather_code || 0;
  const desc = WX_DESC[code] || '';
  const cloudCover = Math.round(c.cloud_cover || 0);
  const wind = Math.round(c.wind_speed_10m || 0);
  const windDirection = compassFromDegrees(c.wind_direction_10m);
  const windArrow = windArrowFromDegrees(c.wind_direction_10m);
  const daily = data.daily || {};
  const hi = Math.round((daily.temperature_2m_max || [])[0] || 0);
  const lo = Math.round((daily.temperature_2m_min || [])[0] || 0);
  const sunrise0 = new Date(daily.sunrise?.[0]);
  const sunset0 = new Date(daily.sunset?.[0]);
  const sunrise1 = new Date(daily.sunrise?.[1] || daily.sunrise?.[0]);
  const now = new Date();
  const isDay = now >= sunrise0 && now < sunset0;
  const isNightNow = !isDay;

  // Celestial position via arc dims (measured on mount; use sensible fallback)
  const arcW = rootRef.current?.querySelector('.wx-arc')?.offsetWidth || 340;
  const arcH = rootRef.current?.querySelector('.wx-arc')?.offsetHeight || 120;
  const pad = arcW * 0.05, usableW = arcW - 2 * pad;
  let progress;
  if (isDay) progress = (now - sunrise0) / (sunset0 - sunrise0);
  else if (now >= sunset0) progress = (now - sunset0) / (sunrise1 - sunset0);
  else {
    const prevSunset = new Date(sunset0); prevSunset.setDate(prevSunset.getDate() - 1);
    progress = (now - prevSunset) / (sunrise0 - prevSunset);
  }
  progress = Math.max(0, Math.min(1, progress));
  const cx = usableW / 2, r = usableW / 2;
  const xPosRaw = progress * usableW;
  const xPos = isDay ? xPosRaw : (usableW - xPosRaw);
  const dx = xPos - cx;
  const yNorm = Math.sqrt(Math.max(0, r * r - dx * dx)) / r;
  const bodySize = isDay ? 72 : 60;
  const celLeft = pad + xPos - bodySize / 2;
  const celBottom = 4 + yNorm * (arcH - bodySize - 8);

  // Dynamic info-side swap: if the celestial body is on the LEFT half of the
  // arc, put the info block on the RIGHT, and vice versa — so the sun/moon
  // never overlaps the temperature/description text.
  const celCenterX = pad + xPos;
  const infoOnRight = celCenterX < (arcW * 0.5);
  const infoSideStyle = infoOnRight
    ? { right: '12px', left: 'auto' }
    : { left: '12px', right: 'auto' };

  let celestial;
  if (isDay) {
    const glowClass = yNorm > 0.9 ? 'zenith' : yNorm < 0.2 ? 'horizon-glow' : '';
    celestial = <div className={`wx-sun ${glowClass}`} />;
  } else {
    const m = getMoonPhase();
    const illum = m.illumination;
    const bodyClass = illum > 0.95 ? 'full' : illum < 0.05 ? 'new' : '';
    const shadowOffset = m.isWaxing ? (1 - illum) * 18 : -(1 - illum) * 18;
    celestial = (
      <div className={`wx-moon-body ${bodyClass}`}>
        <div className="wx-moon-shadow" style={{ left: shadowOffset + 'px' }} />
      </div>
    );
  }

  const fmtTime = dt => {
    const h = dt.getHours(), m = dt.getMinutes();
    return (h % 12 || 12) + ':' + (m < 10 ? '0' : '') + m + (h < 12 ? 'a' : 'p');
  };

  // Hourly strip: now + every 2h for next 10h (6 slots)
  const nowHr = now.getHours();
  const hrs = (data.hourly || {}).temperature_2m || [];
  const hrCodes = (data.hourly || {}).weather_code || [];
  const hours = [];
  for (let offset = 0; offset <= 10; offset += 2) {
    const i = nowHr + offset;
    if (i >= hrs.length) break;
    const h = i % 24;
    const hLabel = offset === 0 ? 'NOW' : h === 0 ? '12a' : h < 12 ? h + 'a' : h === 12 ? '12p' : (h - 12) + 'p';
    hours.push({ label: hLabel, temp: Math.round(hrs[i]), icon: WX_CODES[hrCodes[i]] || '', now: offset === 0 });
  }

  const phaseNames = ['New Moon','Waxing Crescent','First Quarter','Waxing Gibbous','Full Moon','Waning Gibbous','Last Quarter','Waning Crescent'];
  const mPhase = getMoonPhase();
  const phaseIdx = Math.floor(mPhase.age / (29.53 / 8)) % 8;
  const descText = isNightNow ? phaseNames[phaseIdx] : desc;
  const hiloText = isNightNow
    ? `avg ${Math.round((hi + lo) / 2)}° · now ${temp}°`
    : `H ${hi}° · L ${lo}°`;

  return (
    <Pane
      title="WEATHER.SYS"
      sub={offline ? 'demo · offline' : (isDay ? 'day' : 'night')}
      chrome={chrome}
      dense={dense}
      className={`pane-weather ${isDay ? 'wx-day' : 'wx-night'}`}
    >
      <div
        ref={rootRef}
        className="pane-weather-root"
        style={{ height: '100%' }}
      >
        {/* scope palette-dependent classes via parent */}
        <div className="wx-timeline">
          <div className="wx-arc">
            <div className="wx-fx" ref={fxRef} />
            <div className="wx-celestial" style={{ left: celLeft + 'px', bottom: celBottom + 'px' }}>
              {celestial}
            </div>
            <div className="wx-sky-cover" />
            <div className="wx-current-info" style={infoSideStyle}>
              <div className="wx-current-main">
                <span className="wx-current-temp">{temp}°</span>
                <div className="wx-current-copy">
                  <span className="wx-current-desc">{descText}</span>
                  <span className="wx-current-hilo">{hiloText}</span>
                </div>
              </div>
              <div className="wx-current-meta">
                <span className="wx-meta-pill">{WX_PLACE}</span>
                <span className="wx-meta-pill">clouds {cloudCover}%</span>
                <span className="wx-meta-pill">wind {wind} {windArrow} {windDirection}</span>
              </div>
            </div>
          </div>
          {!compact && (
            <div className="wx-hours">
              <span className="wx-rise-set rise">↑{fmtTime(sunrise0)}</span>
              {hours.map((h, i) => (
                <div key={i} className={`wx-hour ${h.now ? 'now' : ''}`}>
                  <div className="wx-h-icon">{h.icon}</div>
                  <div className="wx-h-temp">{h.temp}°</div>
                  <div className="wx-h-time">{h.label}</div>
                </div>
              ))}
              <span className="wx-rise-set set">{fmtTime(sunset0)}↓</span>
            </div>
          )}
        </div>
      </div>
    </Pane>
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// IOS HERO — weather backdrop + Monday-voice micro-facts.
// Minimal weather (sky gradient + single SVG/CSS body + current temp), designed
// to sit BEHIND readable text. The rich WeatherPane still lives on kiosk + mac.
// ─────────────────────────────────────────────────────────────────────────────
// Compute Easter via Gauss algorithm — used for Easter / Good Friday detection
function computeEaster(y) {
  const a = y % 19, b = Math.floor(y / 100), c = y % 100;
  const d = Math.floor(b / 4), e = b % 4;
  const f = Math.floor((b + 8) / 25);
  const g = Math.floor((b - f + 1) / 3);
  const h = (19 * a + b - d - g + 15) % 30;
  const i = Math.floor(c / 4), k = c % 4;
  const L = (32 + 2 * e + 2 * i - h - k) % 7;
  const m2 = Math.floor((a + 11 * h + 22 * L) / 451);
  const month = Math.floor((h + L - 7 * m2 + 114) / 31);
  const day = ((h + L - 7 * m2 + 114) % 31) + 1;
  return { m: month, d: day };
}

// Returns a holiday/observance label for `date`, or null if none.
// Covers US federal holidays + a handful of popular observances. Floating
// dates (MLK Day, Thanksgiving, Easter, Good Friday) are computed.
function getHoliday(date = new Date()) {
  const y = date.getFullYear(), m = date.getMonth() + 1, d = date.getDate();
  const nthOfMonth = (n, weekday, month) => {
    const first = new Date(y, month - 1, 1);
    const offset = (weekday - first.getDay() + 7) % 7;
    return 1 + offset + (n - 1) * 7;
  };
  const lastOfMonth = (weekday, month) => {
    const last = new Date(y, month, 0);
    const offset = (last.getDay() - weekday + 7) % 7;
    return last.getDate() - offset;
  };
  const fixed = {
    '1-1': "New Year's Day", '2-2': 'Groundhog Day', '2-14': "Valentine's Day",
    '3-17': "St. Patrick's Day", '4-1': "April Fool's", '4-22': 'Earth Day',
    '5-5': 'Cinco de Mayo', '6-14': 'Flag Day', '6-19': 'Juneteenth',
    '7-4': 'Independence Day', '10-31': 'Halloween', '11-11': 'Veterans Day',
    '12-24': 'Christmas Eve', '12-25': 'Christmas', '12-31': "New Year's Eve",
  };
  const fk = `${m}-${d}`;
  if (fixed[fk]) return fixed[fk];
  if (m === 1 && d === nthOfMonth(3, 1, 1)) return 'MLK Day';
  if (m === 2 && d === nthOfMonth(3, 1, 2)) return "Presidents' Day";
  if (m === 5 && d === nthOfMonth(2, 0, 5)) return "Mother's Day";
  if (m === 5 && d === lastOfMonth(1, 5)) return 'Memorial Day';
  if (m === 6 && d === nthOfMonth(3, 0, 6)) return "Father's Day";
  if (m === 9 && d === nthOfMonth(1, 1, 9)) return 'Labor Day';
  if (m === 10 && d === nthOfMonth(2, 1, 10)) return "Indigenous Peoples' Day";
  if (m === 11 && d === nthOfMonth(4, 4, 11)) return 'Thanksgiving';
  const easter = computeEaster(y);
  if (m === easter.m && d === easter.d) return 'Easter';
  const gf = new Date(y, easter.m - 1, easter.d); gf.setDate(gf.getDate() - 2);
  if (m === gf.getMonth() + 1 && d === gf.getDate()) return 'Good Friday';
  return null;
}

// Build a one-line description of the day's weather + an optional deadpan quip.
// Drives the small text under the sun: "rain all day · (sad song day)".
function describeDay(data) {
  if (!data) return { line: '', quip: '' };
  const now = new Date();
  const c = data.current || {};
  const daily = data.daily || {};
  const hourly = data.hourly || {};
  const code = c.weather_code || 0;
  const cloud = c.cloud_cover || 0;
  const wind = c.wind_speed_10m || 0;
  const hi = Math.round(daily.temperature_2m_max?.[0] || 0);

  const isRain = (k) => [51,53,55,61,63,65,80,81,82,95,96,99].includes(k);
  const isSnow = (k) => [71,73,75].includes(k);
  const times = hourly.time || [];
  const codes = hourly.weather_code || [];
  const amCodes = [], pmCodes = [];
  for (let i = 0; i < Math.min(times.length, 48); i++) {
    const t = new Date(times[i]);
    if (t.toDateString() !== now.toDateString()) continue;
    if (t.getHours() < 12) amCodes.push(codes[i]);
    else pmCodes.push(codes[i]);
  }
  const rainAm = amCodes.some(isRain), rainPm = pmCodes.some(isRain);
  const snowAny = amCodes.some(isSnow) || pmCodes.some(isSnow) || isSnow(code);

  let line;
  if (snowAny) line = 'snow';
  else if (rainAm && rainPm) line = 'rain all day';
  else if (rainAm && !rainPm) line = 'rain am, clears';
  else if (!rainAm && rainPm) line = 'rain later';
  else if (cloud >= 80 || code === 3) line = 'overcast';
  else if (cloud >= 40) line = 'partly cloudy';
  else if (hi >= 85) line = 'sunny & hot';
  else if (hi <= 40) line = 'sunny & cold';
  else line = 'clear';
  if (wind >= 18 && !snowAny && line !== 'rain all day') line += ', windy';

  const quipMap = {
    'snow': '(stay in)',
    'rain all day': '(sad song day)',
    'rain am, clears': '(wet shoes)',
    'rain later': '(bring a jacket)',
    'overcast': '(soup weather)',
    'sunny & hot': '(hydrate)',
    'sunny & cold': '(deceptive)',
  };
  // strip wind modifier for quip lookup
  const base = line.split(',')[0].trim();
  const quip = quipMap[base] || '';
  return { line, quip };
}

function IosHero() {
  const [wx, setWx] = useState(null);
  useEffect(() => {
    const url = `https://api.open-meteo.com/v1/forecast?latitude=${WX_LAT}&longitude=${WX_LON}`
      + `&current=temperature_2m,weather_code,cloud_cover,precipitation,wind_speed_10m`
      + `&hourly=weather_code`
      + `&daily=sunrise,sunset,temperature_2m_max,temperature_2m_min`
      + `&temperature_unit=fahrenheit&wind_speed_unit=mph&timezone=${encodeURIComponent(WX_TZ)}&forecast_days=2`;
    fetch(url).then(r => r.json()).then(setWx).catch(() => setWx(wxDemoData()));
  }, []);

  const now = new Date();
  const sunrise = wx?.daily?.sunrise?.[0] ? new Date(wx.daily.sunrise[0]) : null;
  const sunset = wx?.daily?.sunset?.[0] ? new Date(wx.daily.sunset[0]) : null;
  const sunrise1 = wx?.daily?.sunrise?.[1] ? new Date(wx.daily.sunrise[1]) : sunrise;
  const isDay = sunrise && sunset ? (now >= sunrise && now < sunset) : (now.getHours() >= 6 && now.getHours() < 20);
  const c = wx?.current || {};
  const code = c.weather_code ?? 1;
  const cloudCover = c.cloud_cover ?? 25;
  const temp = Math.round(c.temperature_2m ?? 64);
  const precip = Number(c.precipitation || 0);
  const rainy = precip > 0.02 || [51,53,55,61,63,65,80,81,82,95,96,99].includes(code);
  const snowy = [71,73,75].includes(code);
  const cloudy = cloudCover >= 40 || [2,3,45,48].includes(code);
  const thunder = [95, 96, 99].includes(code);

  // Celestial body stays pinned to upper-right corner. We still use sunrise/
  // sunset timing to trigger a warm "horizon glow" variant during the ~30-min
  // windows around each event, without physically moving the body.
  const bodySize = 66;
  const celLeft = 390 - 16 - bodySize;     // ~18px inset from right edge
  const celBottom = 180 - 16 - bodySize;   // ~16px inset from top
  let nearHorizon = false;
  if (sunrise && sunset) {
    const mins = 30 * 60 * 1000;
    nearHorizon =
      Math.abs(now - sunrise) < mins ||
      Math.abs(now - sunset) < mins;
  }

  // Moon phase
  const moonPhase = getMoonPhase();
  const moonClass = moonPhase.illumination > 0.95 ? 'full' : moonPhase.illumination < 0.05 ? 'new' : '';
  const moonShadowOffset = (moonPhase.isWaxing ? (1 - moonPhase.illumination) * 70 : -(1 - moonPhase.illumination) * 70);

  // Star field — stable positions per mount so they don't jump on re-render
  const stars = useMemo(() => {
    const out = [];
    for (let i = 0; i < 48; i++) {
      const sz = Math.random();
      const size = sz < 0.7 ? 1 : sz < 0.92 ? 1.5 : 2.2;
      out.push({
        left: Math.random() * 100,
        top: Math.random() * 62,     // upper 62% of hero so they stay above horizon + text
        size,
        opacity: 0.45 + Math.random() * 0.45,
        tw: (2.2 + Math.random() * 3.2).toFixed(1) + 's',
        td: (Math.random() * 3).toFixed(1) + 's',
      });
    }
    return out;
  }, []);

  return (
    <div className={`ios-hero ${isDay ? 'day' : 'night'}`}>
      {/* Stars behind everything at night */}
      {!isDay && (
        <div className="ios-hero-stars">
          {stars.map((s, i) => (
            <div
              key={i}
              className="ios-hero-star"
              style={{
                left: s.left + '%', top: s.top + '%',
                width: s.size + 'px', height: s.size + 'px',
                '--base-opacity': s.opacity, '--tw': s.tw, '--td': s.td,
              }}
            />
          ))}
        </div>
      )}

      {/* Celestial body — pinned upper-right (CSS), hero can grow freely below */}
      <div className="ios-hero-icon">
        {isDay ? (
          <div className={`ios-hero-sun ${nearHorizon ? 'horizon' : ''}`} />
        ) : (
          <div className={`ios-hero-moon ${moonClass}`}>
            <div className="ios-hero-moon-shadow" style={{ left: moonShadowOffset + '%' }} />
          </div>
        )}
      </div>
      {/* 5-layer cloud band behind the text — more defined, spans full width */}
      {cloudy && <div className="ios-hero-cloud c-1" />}
      {cloudy && <div className="ios-hero-cloud c-2" />}
      {cloudy && cloudCover >= 45 && <div className="ios-hero-cloud c-3" />}
      {cloudy && cloudCover >= 60 && <div className="ios-hero-cloud c-4" />}
      {cloudy && cloudCover >= 75 && <div className="ios-hero-cloud c-5" />}
      {rainy && (
        <div className="ios-hero-rain">
          {Array.from({length: 14}).map((_, i) => (
            <div key={i} className="wx-drop" style={{
              left: (i * 7 + Math.random() * 3) + '%',
              height: (10 + Math.random() * 10) + 'px',
              animationDuration: (0.6 + Math.random() * 0.7) + 's',
              animationDelay: (Math.random() * 0.6) + 's',
            }} />
          ))}
        </div>
      )}
      {snowy && (
        <div className="ios-hero-snow">
          {Array.from({length: 12}).map((_, i) => (
            <div key={i} className="wx-flake" style={{
              left: (i * 8 + Math.random() * 4) + '%',
              width: (2 + Math.random() * 3) + 'px', height: (2 + Math.random() * 3) + 'px',
              animationDuration: (3 + Math.random() * 4) + 's, ' + (2 + Math.random() * 3) + 's',
              animationDelay: (Math.random() * 3) + 's, ' + (Math.random() * 2) + 's',
            }} />
          ))}
        </div>
      )}
      <div className="ios-hero-temp">{temp}<span className="ios-hero-temp-unit">°</span></div>
      {(() => {
        const desc = describeDay(wx);
        if (!desc.line) return null;
        return (
          <div className="ios-hero-wxdesc">
            {desc.line}
            {desc.quip && <span className="wxquip">{desc.quip}</span>}
          </div>
        );
      })()}

      {/* Lightning when thunderstorm, day or night */}
      {thunder && <div className="ios-hero-lightning" />}

      {/* Horizon silhouette — sun/moon appear to rise/set behind it */}
      <div className="ios-hero-horizon">
        <svg viewBox="0 0 390 28" preserveAspectRatio="none">
          {/* Back range (softer) */}
          <path
            d="M0,28 L0,18 L30,12 L60,16 L95,8 L135,14 L170,6 L210,12 L250,4 L290,10 L330,6 L370,12 L390,9 L390,28 Z"
            fill="rgba(8,12,20,0.55)"
          />
          {/* Front ridge (sharper) */}
          <path
            d="M0,28 L0,22 L22,18 L48,22 L78,16 L110,20 L138,14 L170,18 L198,12 L232,16 L262,10 L298,14 L330,8 L362,14 L390,10 L390,28 Z"
            fill="rgba(5,8,14,0.88)"
          />
        </svg>
      </div>
      {/* Day + date top-left; holiday badge underneath when applicable */}
      <div className="ios-hero-daydate">
        <div className="ios-hero-daydate-main">
          {now.toLocaleDateString('en-US', { weekday: 'short' }).toUpperCase()}
        </div>
        <div className="ios-hero-daydate-sub">
          {now.toLocaleDateString('en-US', { month: 'short', day: 'numeric' }).toUpperCase()}
        </div>
        {(() => {
          const h = getHoliday(now);
          return h ? <div className="ios-hero-holiday">· {h}</div> : null;
        })()}
      </div>
      {/* Headline + mood + micro-facts live in the same area, wrap-constrained
          so they never slide under the sun. */}
      <div className="ios-hero-text">
        <RotatingHeadline />
        <div className="ios-mood">{DAILY_BRIEF.mood.toLowerCase()}</div>
        <MicroFactsTicker />
      </div>
    </div>
  );
}

// Rotating headline — cycles through HEADLINES, optionally refreshed by Claude.
function RotatingHeadline() {
  const [pool, setPool] = useState(() => {
    try {
      const cached = JSON.parse(localStorage.getItem('alfredo:headlines') || 'null');
      if (cached && Date.now() - cached.at < 4 * 60 * 60 * 1000) return cached.items;
    } catch {}
    return HEADLINES;
  });
  const [idx, setIdx] = useState(() => Math.floor(Math.random() * HEADLINES.length));

  // Rotate every 22s
  useEffect(() => {
    if (!pool.length) return;
    const id = setInterval(() => setIdx(i => (i + 1) % pool.length), 22000);
    return () => clearInterval(id);
  }, [pool.length]);

  // Periodic LLM refresh with Monday-voice style + context
  useEffect(() => {
    const refresh = async () => {
      const apiKey = localStorage.getItem('alfredo:anthropic_key');
      if (!apiKey || !window.streamClaude) return;
      const sys = [
        'Write 10 one-line dashboard headlines for an ADHD-inattentive operator.',
        'Tone: simple, direct, helpful, encouraging with a bite. Monday-voice (deadpan, mildly roasty).',
        'Each line ≤ 60 chars, lowercase preferred, no markdown, no emoji, no numbering.',
        'Return exactly 10 lines, newline-separated. Nothing else.',
        'Examples: "less thinking, more doing." / "the list doesn\'t shrink by staring at it." / "call it done at 80%. ship."',
      ].join('\n');
      try {
        let out = '';
        await window.streamClaude({
          apiKey, system: sys, userText: 'generate 10',
          onDelta: (c) => { out += c; },
          model: 'claude-haiku-4-5-20251001',
          maxTokens: 500,
        });
        const lines = out.split('\n').map(s => s.trim()).filter(s => s.length > 6 && s.length < 80).slice(0, 10);
        if (lines.length >= 5) {
          setPool(lines);
          try { localStorage.setItem('alfredo:headlines', JSON.stringify({ at: Date.now(), items: lines })); } catch {}
        }
      } catch {}
    };
    refresh();
    const id = setInterval(refresh, 4 * 60 * 60 * 1000);
    return () => clearInterval(id);
  }, []);

  return <div className="ios-headline">{pool[idx % pool.length]}</div>;
}

function MicroFactsTicker() {
  // Start with the seed list; refresh with LLM-generated quips every 2h when
  // an API key is available. Cached in localStorage so reloads reuse them.
  const [facts, setFacts] = useState(() => {
    try {
      const cached = JSON.parse(localStorage.getItem('alfredo:microfacts') || 'null');
      if (cached && Date.now() - cached.at < 2 * 60 * 60 * 1000) return cached.items;
    } catch {}
    return MICRO_FACTS;
  });
  const [iA, setA] = useState(0);
  const [iB, setB] = useState(1);

  // Refresh generator: ask Claude for 8 fresh Monday-voice quips tailored to
  // current context (time, weekday, known projects).
  const refresh = async () => {
    const apiKey = localStorage.getItem('alfredo:anthropic_key');
    if (!apiKey || !window.streamClaude) return;
    const now = new Date();
    const sys = [
      'You write one-line micro-facts in a deadpan, dry, mildly mean "Monday" persona for a personal dashboard.',
      'Each line: max 90 chars, lowercase preferred, specific, grounded in the user\'s life.',
      'Mix topics: sleep, steps, coffee, hydration, screen time, inbox count, active projects, upcoming events, weather adjacency.',
      'NO greetings, NO emoji, NO markdown. One per line. Exactly 8 lines.',
      `Context: ${now.toLocaleString()}, day=${now.toLocaleDateString('en-US',{weekday:'long'})}.`,
      `Projects: ${PROJECTS.map(p=>p.name).join(', ')}.`,
      `Sample tone: "you slept 5h 12m. brace." / "coffee #2 was at 10:14. we\'re tracking."`,
      'Return ONLY the 8 lines, newline-separated. No numbering.',
    ].join('\n');
    try {
      let out = '';
      await window.streamClaude({
        apiKey, system: sys, userText: 'generate 8 fresh quips',
        onDelta: (c) => { out += c; },
        model: 'claude-haiku-4-5-20251001',   // cheaper, plenty capable
        maxTokens: 500,
      });
      const lines = out.split('\n').map(s => s.trim()).filter(s => s.length > 0 && s.length < 140).slice(0, 8);
      if (lines.length >= 4) {
        setFacts(lines);
        try { localStorage.setItem('alfredo:microfacts', JSON.stringify({ at: Date.now(), items: lines })); } catch {}
      }
    } catch {}
  };

  useEffect(() => {
    refresh();
    const id = setInterval(refresh, 2 * 60 * 60 * 1000); // every 2h
    return () => clearInterval(id);
  }, []);

  // Rotation
  useEffect(() => {
    if (!facts.length) return;
    let tick = 0;
    const id = setInterval(() => {
      tick++;
      if (tick % 2) setA(i => (i + 2) % facts.length);
      else setB(i => (i + 2) % facts.length);
    }, 6000);
    return () => clearInterval(id);
  }, [facts.length]);

  if (!facts.length) return null;
  return (
    <div className="ios-microfacts">
      <div key={`a-${iA}`} className="ios-microfact">{facts[iA % facts.length]}</div>
      <div key={`b-${iB}`} className="ios-microfact">{facts[iB % facts.length]}</div>
    </div>
  );
}

Object.assign(window, {
  Pane, Conf, fadeOpacity, CollapseContext,
  DailyBrief, CalendarPane, InboxPane, ProjectsPane, ScratchPane, PulsePane, TTYPane, WeatherPane,
  IosHero, IosTextBlock, MicroFactsTicker,
  StatusBar,
});
