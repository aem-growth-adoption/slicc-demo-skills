<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8"/>
  <link rel="icon" href="rocket" />
  <meta name="viewport" content="width=device-width,initial-scale=1"/>
  <title>{{SLUG}} — migration</title>
  <style>
    :root {
      --bg: #0c1222;
      --surface: #151d30;
      --sunken: #0a0f1c;
      --accent: #3b82f6;
      --accent-deep: #2563eb;
      --accent-glow: rgba(59,130,246,0.12);
      --success: #22c55e;
      --success-glow: rgba(34,197,94,0.10);
      --fg: rgba(248,250,252,0.95);
      --fg-muted: rgba(248,250,252,0.65);
      --fg-dim: rgba(248,250,252,0.40);
      --fg-faint: rgba(248,250,252,0.20);
      --hairline: rgba(248,250,252,0.08);
      --hairline-soft: rgba(248,250,252,0.05);
      --font: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      --mono: "SF Mono", "JetBrains Mono", ui-monospace, monospace;
      --ease: cubic-bezier(0.16, 1, 0.3, 1);
    }

    *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }

    html, body {
      height: 100%; background: var(--bg); color: var(--fg);
      font: 400 14px/1.5 var(--font);
      -webkit-font-smoothing: antialiased;
    }

    .wrap { display: flex; flex-direction: column; height: 100%; overflow: hidden; }

    /* ── Header ── */
    .header {
      display: flex; align-items: center; justify-content: space-between;
      height: 44px; flex: none; padding: 0 16px;
      background: var(--surface); border-bottom: 1px solid var(--hairline);
    }
    .header-left { display: flex; align-items: center; gap: 10px; }
    .header-badge {
      font: 600 10px/1 var(--mono); letter-spacing: 0.14em;
      text-transform: uppercase; color: var(--accent);
    }
    .header-url { font-size: 12px; color: var(--fg-dim); overflow: hidden; text-overflow: ellipsis; white-space: nowrap; max-width: 200px; }

    /* ── Progress bar ── */
    .progress-bar {
      display: flex; align-items: center; gap: 10px;
      padding: 10px 16px; background: var(--surface);
      border-bottom: 1px solid var(--hairline);
    }
    .progress-track { flex: 1; height: 3px; background: var(--hairline); border-radius: 2px; overflow: hidden; }
    .progress-fill { height: 100%; background: var(--accent); border-radius: 2px; transition: width .6s var(--ease); }
    .progress-label { font: 500 10px/1 var(--mono); color: var(--fg-faint); white-space: nowrap; }

    /* ── Steps ── */
    .steps-scroll { flex: 1; overflow-y: auto; scrollbar-width: thin; scrollbar-color: var(--hairline) transparent; }
    .steps { padding: 16px; display: flex; flex-direction: column; gap: 0; }

    .step { display: flex; flex-direction: column; position: relative; }
    .step::before {
      content: ''; position: absolute; left: 13px; top: 36px; bottom: -4px;
      width: 1px; background: var(--hairline);
    }
    .step:last-child::before { display: none; }

    .step-row {
      display: flex; align-items: flex-start; gap: 12px;
      padding: 12px 14px 12px 0; border-radius: 10px; transition: background .15s;
    }

    .step[data-status="active"] .step-row {
      background: var(--accent-glow);
      border-left: 3px solid var(--accent);
      padding-left: 11px; border-radius: 0 10px 10px 0;
    }
    .step[data-status="done"] .step-row {
      background: var(--surface);
      border: 1px solid var(--hairline);
      border-radius: 10px; margin-bottom: 4px; padding-left: 14px;
    }
    .step[data-status="pending"] .step-row {
      opacity: 0.35; padding-left: 0;
    }

    /* ── Step icon ── */
    .step-icon {
      width: 26px; height: 26px; border-radius: 50%; flex: none;
      display: grid; place-items: center; font-size: 11px; margin-top: 1px;
    }
    .step-icon.done { background: var(--success); color: #fff; font-weight: 700; }
    .step-icon.active { background: var(--accent); color: #fff; }
    .step-icon.pending { background: transparent; border: 1.5px solid var(--fg-faint); }

    .step-content { flex: 1; min-width: 0; display: flex; flex-direction: column; gap: 3px; }
    .step-label {
      font: 600 13px/1.2 var(--font); color: var(--fg);
      display: flex; align-items: center; gap: 8px;
    }
    .step-meta { font: 400 12px/1.4 var(--font); color: var(--fg-dim); }
    .step-timer {
      font: 500 10px/1 var(--mono); color: var(--fg-faint);
      margin-left: auto; flex: none; padding-top: 2px;
    }
    .step[data-status="active"] .step-timer { color: var(--accent); }
    .step[data-status="done"] .step-timer { color: var(--success); }
    .step-link {
      font: 500 11px/1 var(--mono); color: var(--accent);
      text-decoration: none;
    }
    .step-link:hover { text-decoration: underline; }

    /* ── Animations ── */
    @keyframes riseIn {
      from { opacity: 0; transform: translateY(6px); }
      to   { opacity: 1; transform: none; }
    }
    @keyframes pulse {
      0%, 100% { opacity: 1; transform: scale(1); }
      50%       { opacity: 0.6; transform: scale(0.85); }
    }
    .stagger > * {
      opacity: 0; animation: riseIn .4s var(--ease) forwards;
      animation-play-state: paused;
    }
    body.ready .stagger > * { animation-play-state: running; }
    .stagger > *:nth-child(1) { animation-delay: .03s; }
    .stagger > *:nth-child(2) { animation-delay: .07s; }
    .stagger > *:nth-child(3) { animation-delay: .11s; }
    .stagger > *:nth-child(4) { animation-delay: .15s; }
    .stagger > *:nth-child(5) { animation-delay: .19s; }
    .stagger > *:nth-child(6) { animation-delay: .23s; }
    .active-dot { animation: pulse 1.4s ease-in-out infinite; }
  </style>
</head>
<body>
  <div class="wrap">
    <div class="header">
      <div class="header-left">
        <span class="header-badge">liftoff</span>
        <span class="header-url">{{URL}}</span>
      </div>
    </div>

    <div class="progress-bar">
      <div class="progress-track">
        <div class="progress-fill" id="progress-fill" style="width:0%"></div>
      </div>
      <span class="progress-label" id="progress-label">0 / 6</span>
    </div>

    <div class="steps-scroll">
      <div class="steps stagger" id="steps-container"></div>
    </div>
  </div>

  <script id="initial-state" type="application/json">
{{INITIAL_STATE_JSON}}
  </script>

  <script>
    var STEPS = [
      { id: 'setup',         label: 'Setup',          icon: '⚙️' },
      { id: 'extraction',    label: 'Extraction',     icon: '🔍' },
      { id: 'decomposition', label: 'Decomposition',  icon: '🧩' },
      { id: 'blocks',        label: 'Blocks',         icon: '🏗️' },
      { id: 'assembly',      label: 'Assembly',       icon: '📦' },
      { id: 'deploy',        label: 'Deploy',         icon: '🚀' }
    ];

    var bakedState = null;
    try { bakedState = JSON.parse(document.getElementById('initial-state').textContent); } catch(e) {}

    var state = {
      steps: STEPS.map(function(s) {
        return { id: s.id, status: 'pending', summary: '', link: null, startedAt: null, completedAt: null };
      })
    };

    function formatDuration(ms) {
      var secs = Math.floor(ms / 1000);
      var m = Math.floor(secs / 60);
      var s = secs % 60;
      if (m > 0) return m + 'm ' + (s < 10 ? '0' : '') + s + 's';
      return s + 's';
    }

    function iconHTML(status) {
      if (status === 'done') return '<span class="step-icon done">✓</span>';
      if (status === 'active') return '<span class="step-icon active active-dot">●</span>';
      return '<span class="step-icon pending"></span>';
    }

    function render() {
      var container = document.getElementById('steps-container');
      container.innerHTML = '';

      state.steps.forEach(function(step, i) {
        var el = document.createElement('div');
        el.className = 'step';
        el.setAttribute('data-status', step.status);

        var linkHtml = step.link
          ? ' <a class="step-link" href="' + step.link + '" target="_blank" rel="noopener">view ↗</a>'
          : '';

        var timerHtml = '';
        if (step.status === 'done' && step.startedAt && step.completedAt) {
          timerHtml = '<span class="step-timer">' + formatDuration(step.completedAt - step.startedAt) + '</span>';
        } else if (step.status === 'active' && step.startedAt) {
          timerHtml = '<span class="step-timer" data-started="' + step.startedAt + '"></span>';
        }

        var meta = step.summary || STEPS[i].label;

        el.innerHTML = '<div class="step-row">' +
          iconHTML(step.status) +
          '<div class="step-content">' +
            '<div class="step-label">' + STEPS[i].label + linkHtml + '</div>' +
            '<div class="step-meta">' + meta + '</div>' +
          '</div>' +
          timerHtml +
        '</div>';

        container.appendChild(el);
      });

      updateProgress();
    }

    function updateProgress() {
      var total = state.steps.length;
      var done = state.steps.filter(function(s) { return s.status === 'done'; }).length;
      var active = state.steps.filter(function(s) { return s.status === 'active'; }).length;
      var pct = Math.round(((done + active * 0.5) / total) * 100);
      document.getElementById('progress-fill').style.width = pct + '%';
      document.getElementById('progress-label').textContent = done + ' / ' + total + ' done';
    }

    // Restore: slicc persisted > baked-in > defaults
    var saved = slicc.getState();
    if (saved && saved.steps && saved.steps.length === STEPS.length) {
      state = saved;
    } else if (bakedState && bakedState.steps && bakedState.steps.length === STEPS.length) {
      state = bakedState;
      slicc.setState(state);
    }

    slicc.on('update', function(data) {
      if (!data || !data.step) return;
      var idx = state.steps.findIndex(function(s) { return s.id === data.step; });
      if (idx === -1) return;

      if (data.status) {
        if (data.status === 'active' && !state.steps[idx].startedAt) {
          state.steps[idx].startedAt = Date.now();
        }
        if (data.status === 'done' && !state.steps[idx].completedAt) {
          state.steps[idx].completedAt = Date.now();
          if (!state.steps[idx].startedAt) state.steps[idx].startedAt = state.steps[idx].completedAt;
        }
        state.steps[idx].status = data.status;
      }
      if (data.summary) state.steps[idx].summary = data.summary;
      if (data.link) state.steps[idx].link = data.link;

      slicc.setState(state);
      render();
    });

    // Live ticker for active steps
    setInterval(function() {
      var timers = document.querySelectorAll('.step-timer[data-started]');
      var now = Date.now();
      timers.forEach(function(el) {
        var started = parseInt(el.getAttribute('data-started'), 10);
        el.textContent = formatDuration(now - started);
      });
    }, 1000);

    render();
    setTimeout(function() { document.body.classList.add('ready'); }, 50);
  </script>
</body>
</html>
