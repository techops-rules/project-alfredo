// Three surfaces: KIOSK (1024x600), MACOS (1280x800), IOS (390x844).
// Each places the same widgets in the right composition for that form factor.

const { useState: useS, useEffect: useE } = React;

// ─────────────────────────────────────────────────────────────────────────────
// KIOSK — hero surface, 7" landscape (1024×600)
// Composition: status bar + 3-col grid
//   col1: DAILY.BRIEF (tall)
//   col2: NEXT.PULSE (top) + CALENDAR (bottom)
//   col3: SCRATCH (top) + INBOX (mid) + PROJECTS (bottom) — but density-dependent
// ─────────────────────────────────────────────────────────────────────────────
function KioskSurface({ chrome, density, confVariant, onFocus, scratch, calendar, projects, children }) {
  const dense = density === 'tight';
  return (
    <div className={`kiosk surface density-${density}`}>
      <StatusBar surface="KIOSK · 7IN" chrome={chrome} />
      <div className="kiosk-grid">
        <div className="kiosk-col kiosk-col-1">
          <DailyBrief chrome={chrome} confVariant={confVariant} onFocus={onFocus} />
        </div>
        <div className="kiosk-col kiosk-col-2">
          <WeatherPane chrome={chrome} dense={dense} />
          <CalendarPane chrome={chrome} dense={dense} calendar={calendar} />
        </div>
        <div className="kiosk-col kiosk-col-3">
          <ScratchPane chrome={chrome} dense={dense} items={scratch.items} onAdd={scratch.onAdd} onInspect={scratch.onInspect} />
          <TTYPane chrome={chrome} dense={dense} />
        </div>
      </div>
      <KioskFootBar />
      {children}
    </div>
  );
}

function KioskFootBar() {
  return (
    <div className="kiosk-footbar">
      <span className="foot-item">⌘ HOLD · WAKE "alfredo"</span>
      <span className="foot-sep">·</span>
      <span className="foot-item">TAP · ADD</span>
      <span className="foot-sep">·</span>
      <span className="foot-item">LONG-PRESS · FOCUS</span>
      <span className="foot-grow" />
      <span className="foot-item foot-faint">ingest cycle in 14m</span>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// MACOS — companion, ~1280×800 in a window chrome
// Composition: left rail (nav + projects) + main 2-col grid
// ─────────────────────────────────────────────────────────────────────────────
function MacosSurface({ chrome, density, confVariant, onFocus, onOpenEmail, sentMails, calendar, projects, children }) {
  const dense = density === 'tight';
  return (
    <div className={`macos-window surface density-${density}`}>
      <div className="macos-titlebar">
        <div className="macos-traffic">
          <span className="tl-dot tl-r"/><span className="tl-dot tl-y"/><span className="tl-dot tl-g"/>
        </div>
        <div className="macos-title">alfredo · external brain</div>
        <div className="macos-titlebar-right">
          <span className="macos-pill">⌘K</span>
        </div>
      </div>
      <div className="macos-body">
        <div className="macos-rail">
          <div className="rail-section">
            <div className="rail-head">SURFACE</div>
            <div className="rail-item active">› TODAY</div>
            <div className="rail-item">  INBOX</div>
            <div className="rail-item">  PROJECTS</div>
            <div className="rail-item">  CALENDAR</div>
            <div className="rail-item">  MEMORY</div>
          </div>
          <div className="rail-section">
            <div className="rail-head">PROJECTS</div>
            {PROJECTS.map((p, i) => (
              <div key={i} className="rail-proj">
                <span className={`proj-health proj-health-${p.health}`} />
                <span>{p.name}</span>
              </div>
            ))}
          </div>
          <div className="rail-section rail-bottom">
            <div className="rail-head">SOURCES</div>
            <div className="rail-source"><span className="status-dot ok"/> gmail.work</div>
            <div className="rail-source"><span className="status-dot ok"/> gmail.life</div>
            <div className="rail-source"><span className="status-dot ok"/> gcal</div>
            <div className="rail-source"><span className="status-dot ok"/> icloud</div>
            <div className="rail-source"><span className="status-dot ok"/> obsidian</div>
            <div className="rail-source"><span className="status-dot warn"/> slack <span className="rail-source-tag">soon</span></div>
          </div>
        </div>
        <div className="macos-main">
          <div className="macos-row macos-row-top">
            <div className="macos-cell macos-cell-wide">
              <DailyBrief chrome={chrome} confVariant={confVariant} onFocus={onFocus} />
            </div>
            <div className="macos-cell">
              <PulsePane chrome={chrome} confVariant={confVariant} dense={dense} />
            </div>
          </div>
          <div className="macos-row macos-row-bot">
            <div className="macos-cell">
              <CalendarPane chrome={chrome} dense={dense} calendar={calendar} />
            </div>
            <div className="macos-cell">
              <InboxPane chrome={chrome} confVariant={confVariant} dense={dense} onOpen={onOpenEmail} sentMails={sentMails} />
            </div>
            <div className="macos-cell macos-cell-tty">
              <TTYPane chrome={chrome} dense={dense} expanded />
            </div>
          </div>
        </div>
      </div>
      {children}
    </div>
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// iOS — primary mobile, 390×844 (iPhone 15 Pro)
// Composition: vertical stack, swipeable section header
// ─────────────────────────────────────────────────────────────────────────────
function IosSurface({ chrome, density, confVariant, onFocus, onOpenEmail, sentMails, scratch, calendar, projects, children }) {
  const [tab, setTab] = useS('TODAY');
  const dense = density === 'tight';

  return (
    <div className={`ios-frame surface density-${density}`}>
      <div className="ios-statusbar">
        <span>{NOW.toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit', hour12: false })}</span>
        <span className="ios-notch" />
        <span className="ios-statusbar-right">
          <svg width="17" height="11" viewBox="0 0 17 11" fill="currentColor"><path d="M1 7h2v3H1zm4-2h2v5H5zm4-2h2v7H9zm4-2h2v9h-2z"/></svg>
          <svg width="15" height="11" viewBox="0 0 15 11" fill="none" stroke="currentColor"><path d="M7.5 3.5c-2 0-3.5 1.2-4.5 2 1-1.5 2.5-3 4.5-3s3.5 1.5 4.5 3c-1-.8-2.5-2-4.5-2zm0 3a1.5 1.5 0 110 3 1.5 1.5 0 010-3z" fill="currentColor" stroke="none"/></svg>
          <svg width="24" height="11" viewBox="0 0 24 11" fill="none"><rect x="0.5" y="0.5" width="20" height="10" rx="2" stroke="currentColor"/><rect x="2" y="2" width="14" height="7" rx="1" fill="currentColor"/><rect x="21" y="3.5" width="2" height="4" rx="1" fill="currentColor"/></svg>
        </span>
      </div>

      {/* Unified hero: day/date top-left, sun+temp top-right,
          headline/mood/micro-facts inside the hero, wrap-safe away from the sun. */}
      <IosHero />

      <div className="ios-scroll">
        {tab === 'TODAY' && (
          <>
            <PulsePane chrome={chrome} confVariant={confVariant} dense={dense} />
            <div className="ios-stack">
              {DAILY_BRIEF.items.map((it, i) => (
                <div key={i} className="ios-priority" style={{ opacity: fadeOpacity(confVariant, it.confidence) }} onClick={() => onFocus && onFocus(it)}>
                  <div className="ios-priority-rank">0{it.rank}</div>
                  <div className="ios-priority-body">
                    <div className="ios-priority-label">
                      <span className={`tag tag-${it.tag.toLowerCase()}`}>{it.tag}</span>
                      <span>{it.label}</span>
                    </div>
                    <div className="ios-priority-why">{it.why}</div>
                    <div className="ios-priority-foot">
                      <Conf value={it.confidence} variant={confVariant} />
                      <span className="ios-priority-source">{it.source}</span>
                    </div>
                  </div>
                </div>
              ))}
            </div>
            <ScratchPane chrome={chrome} dense={dense} items={scratch.items} onAdd={scratch.onAdd} onInspect={scratch.onInspect} />
          </>
        )}
        {tab === 'INBOX' && <InboxPane chrome={chrome} confVariant={confVariant} dense={dense} onOpen={onOpenEmail} sentMails={sentMails} />}
        {tab === 'CAL' && <CalendarPane chrome={chrome} dense={dense} calendar={calendar} />}
        {tab === 'PROJ' && <ProjectsPane chrome={chrome} dense={dense} projects={projects} />}
        {tab === 'TTY' && <TTYPane chrome={chrome} dense={dense} expanded />}
      </div>

      {/* Bottom tab bar — iOS-native placement, above the home indicator */}
      <div className="ios-tabs ios-tabs-bottom">
        {['TODAY', 'INBOX', 'CAL', 'PROJ', 'TTY'].map(t => (
          <button key={t} className={`ios-tab ${tab === t ? 'active' : ''}`} onClick={() => setTab(t)}>{t}</button>
        ))}
      </div>

      <div className="ios-homebar" />
      {children}
    </div>
  );
}

Object.assign(window, { KioskSurface, MacosSurface, IosSurface });
