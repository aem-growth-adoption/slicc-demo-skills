<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8"/>
  <link rel="icon" href="party-popper" />
  <meta name="viewport" content="width=device-width,initial-scale=1"/>
  <title>{{SLUG}} — complete</title>
  <style>
    :root {
      --bg: #0c1222;
      --surface: #151d30;
      --sunken: #0a0f1c;
      --accent: #3b82f6;
      --accent-deep: #2563eb;
      --success: #22c55e;
      --success-glow: rgba(34,197,94,0.08);
      --success-border: rgba(34,197,94,0.22);
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
      font: 400 14px/1.55 var(--font);
      -webkit-font-smoothing: antialiased;
    }

    @keyframes riseIn {
      from { opacity: 0; transform: translateY(8px); }
      to   { opacity: 1; transform: none; }
    }
    @keyframes shimmer {
      0% { background-position: -200% 0; }
      100% { background-position: 200% 0; }
    }

    .stagger > * {
      opacity: 0; animation: riseIn .5s var(--ease) forwards;
      animation-play-state: paused;
    }
    body.ready .stagger > * { animation-play-state: running; }
    .stagger > *:nth-child(1) { animation-delay: .05s; }
    .stagger > *:nth-child(2) { animation-delay: .15s; }
    .stagger > *:nth-child(3) { animation-delay: .25s; }
    .stagger > *:nth-child(4) { animation-delay: .35s; }

    .wrap { display: flex; flex-direction: column; height: 100vh; }

    .header {
      display: flex; align-items: center; gap: 10px;
      height: 44px; flex: none; padding: 0 16px;
      background: var(--surface); border-bottom: 1px solid var(--hairline);
    }
    .header-badge {
      font: 600 10px/1 var(--mono); letter-spacing: 0.14em;
      text-transform: uppercase; color: var(--success);
    }
    .header-text { font-size: 12px; color: var(--fg-dim); }

    .body {
      flex: 1; overflow-y: auto; padding: 20px 16px;
      display: flex; flex-direction: column; gap: 16px;
    }

    /* ── Success banner ── */
    .banner {
      text-align: center; padding: 28px 20px;
      background: linear-gradient(135deg, rgba(34,197,94,0.06) 0%, rgba(59,130,246,0.06) 100%);
      border: 1px solid var(--success-border); border-radius: 14px;
    }
    .banner-emoji { font-size: 36px; margin-bottom: 12px; }
    .banner-title {
      font: 600 20px/1.2 var(--font); color: var(--fg);
      margin-bottom: 6px;
    }
    .banner-sub { font-size: 13px; color: var(--fg-muted); }

    /* ── Live URL card ── */
    .live-card {
      background: var(--success-glow);
      border: 1px solid var(--success-border);
      border-radius: 12px; padding: 14px 16px;
      display: flex; align-items: center; justify-content: space-between; gap: 12px;
    }
    .live-left { display: flex; flex-direction: column; gap: 3px; }
    .live-label {
      font: 600 10px/1 var(--mono); letter-spacing: 0.14em;
      text-transform: uppercase; color: var(--success);
    }
    .live-url {
      font: 500 12px/1.3 var(--mono); color: var(--fg);
      word-break: break-all;
    }
    .live-btn {
      display: inline-flex; align-items: center; gap: 6px;
      padding: 8px 14px; border: 1px solid var(--success-border);
      border-radius: 8px; background: var(--surface);
      font: 600 11px/1 var(--mono); letter-spacing: 0.06em;
      text-transform: uppercase; color: var(--success);
      cursor: pointer; text-decoration: none; flex: none;
      transition: all .18s var(--ease);
    }
    .live-btn:hover { background: var(--success); color: #fff; border-color: var(--success); }

    /* ── Stats ── */
    .stats { display: flex; gap: 10px; }
    .stat {
      flex: 1; background: var(--surface);
      border: 1px solid var(--hairline); border-radius: 10px;
      padding: 14px 14px; display: flex; flex-direction: column; gap: 4px;
    }
    .stat-val { font: 700 22px/1 var(--font); letter-spacing: -0.02em; color: var(--fg); }
    .stat-label {
      font: 500 10px/1 var(--mono); letter-spacing: 0.08em;
      text-transform: uppercase; color: var(--fg-dim);
    }

    /* ── Next steps ── */
    .next {
      background: var(--surface); border: 1px solid var(--hairline);
      border-radius: 12px; padding: 16px;
    }
    .next-header {
      font: 600 10px/1 var(--mono); letter-spacing: 0.14em;
      text-transform: uppercase; color: var(--accent);
      margin-bottom: 12px;
    }
    .next-list { list-style: none; display: flex; flex-direction: column; gap: 8px; }
    .next-item {
      display: flex; align-items: center; gap: 12px;
      padding: 10px 12px; background: var(--bg);
      border: 1px solid var(--hairline); border-radius: 8px;
      transition: all .18s var(--ease);
    }
    .next-item:hover { border-color: rgba(248,250,252,0.14); }
    .next-icon {
      width: 32px; height: 32px; border-radius: 8px;
      background: var(--sunken); display: grid; place-items: center;
      font-size: 15px; flex: none;
    }
    .next-body { display: flex; flex-direction: column; gap: 2px; flex: 1; }
    .next-title { font: 600 13px/1.2 var(--font); color: var(--fg); }
    .next-desc { font-size: 12px; color: var(--fg-dim); line-height: 1.35; }
    .next-link {
      font: 600 11px/1 var(--mono); color: var(--accent);
      text-decoration: none; flex: none;
    }
    .next-link:hover { text-decoration: underline; }
  </style>
</head>
<body>
<div class="wrap">
  <div class="header">
    <span class="header-badge">✓ migrated</span>
    <span class="header-text">your page is live on AEM Edge Delivery</span>
  </div>

  <div class="body stagger">
    <div class="banner">
      <div class="banner-emoji">🚀</div>
      <div class="banner-title">Migration complete</div>
      <div class="banner-sub" id="source-url"></div>
    </div>

    <div class="live-card">
      <div class="live-left">
        <span class="live-label">preview url</span>
        <span class="live-url" id="live-url"></span>
      </div>
      <a class="live-btn" id="live-link" href="#" target="_blank" rel="noopener">open ↗</a>
    </div>

    <div class="stats" id="stats"></div>

    <div class="next">
      <div class="next-header">next steps</div>
      <ul class="next-list" id="next-steps"></ul>
    </div>
  </div>
</div>

<script id="complete-data" type="application/json">
{{COMPLETE_JSON}}
</script>

<script>
  var DATA = JSON.parse(document.getElementById('complete-data').textContent);

  function esc(s) {
    return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
  }

  document.getElementById('source-url').textContent = DATA.url || '';
  document.getElementById('live-url').textContent = DATA.previewUrl || '';
  var link = document.getElementById('live-link');
  link.href = DATA.previewUrl || '#';

  var statsEl = document.getElementById('stats');
  statsEl.innerHTML = (DATA.stats || []).map(function(s) {
    return '<div class="stat"><span class="stat-val">' + esc(s.value) + '</span><span class="stat-label">' + esc(s.label) + '</span></div>';
  }).join('');

  var nextEl = document.getElementById('next-steps');
  nextEl.innerHTML = (DATA.nextSteps || []).map(function(s) {
    var linkHtml = s.url
      ? '<a class="next-link" href="' + esc(s.url) + '" target="_blank" rel="noopener">' + esc(s.linkLabel || 'open') + ' ↗</a>'
      : '';
    return '<li class="next-item">' +
      '<span class="next-icon">' + (s.icon || '→') + '</span>' +
      '<div class="next-body"><span class="next-title">' + esc(s.title) + '</span><span class="next-desc">' + esc(s.description) + '</span></div>' +
      linkHtml +
    '</li>';
  }).join('');

  setTimeout(function() { document.body.classList.add('ready'); }, 50);
  slicc.on('update', function() {});
</script>
</body>
</html>
