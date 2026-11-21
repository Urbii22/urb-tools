/* URB-Tools — web estática (GitHub Pages)
 * Sin dependencias. Cada bloque se activa solo si su elemento existe en la página:
 *   [data-copy]   botones de copiar
 *   #netbg        fondo de red animado del hero (Inicio)
 *   #term         terminal que se escribe sola (Inicio)
 *   [data-tabs]   pestañas GOD / RED / BLUE (Entornos)
 *   .rv / .rv2    aparición al hacer scroll si el navegador no soporta animation-timeline
 */
(function () {
  'use strict';

  var reduce = false;
  try { reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches; } catch (e) { /* sin matchMedia */ }

  /* ---------- Copiar ---------- */
  var COPY_TEXTS = {
    install: 'git clone https://github.com/Urbii22/urb-tools.git\ncd urb-tools && ./install.sh\nurb',
    path: 'echo \'export PATH="$HOME/.local/bin:$PATH"\' >> ~/.zshrc && source ~/.zshrc'
  };

  Array.prototype.forEach.call(document.querySelectorAll('[data-copy]'), function (btn) {
    var idle = btn.textContent;
    btn.addEventListener('click', function () {
      var text = COPY_TEXTS[btn.getAttribute('data-copy')];
      if (!text) return;
      var done = function (ok) {
        btn.textContent = ok ? 'Copiado ✓' : 'Cópialo a mano';
        clearTimeout(btn._urbT);
        btn._urbT = setTimeout(function () { btn.textContent = idle; }, 2000);
      };
      if (navigator.clipboard && window.isSecureContext) {
        navigator.clipboard.writeText(text).then(function () { done(true); }, function () { done(false); });
      } else {
        done(false);
      }
    });
  });

  /* ---------- Aparición al hacer scroll (fallback) ---------- */
  var supportsTimeline = window.CSS && CSS.supports && CSS.supports('animation-timeline: view()');
  if (!supportsTimeline && !reduce && 'IntersectionObserver' in window) {
    document.documentElement.classList.add('io');
    var revealIO = new IntersectionObserver(function (entries) {
      entries.forEach(function (en) {
        if (en.isIntersecting) { en.target.classList.add('in'); revealIO.unobserve(en.target); }
      });
    }, { rootMargin: '0px 0px -8% 0px' });
    Array.prototype.forEach.call(document.querySelectorAll('.rv, .rv2'), function (el) { revealIO.observe(el); });
  }

  /* ---------- Fondo de red animado ---------- */
  var bg = document.getElementById('netbg');
  if (bg && bg.getContext) initNet(bg);

  function initNet(el) {
    var ctx = el.getContext('2d');
    if (!ctx) return;
    var dpr = Math.min(window.devicePixelRatio || 1, 2);
    var nodes = [], packets = [];
    var pcols = ['#00e5ff', '#00e5ff', '#00ff87', '#ffc400', '#ff4545', '#3b93ff'];
    var mouse = { x: -9999, y: -9999 };
    var W = 0, H = 0, raf = 0, visible = true;
    var LINK = 140, MR = 200;

    function mk() {
      return { x: Math.random() * W, y: Math.random() * H, vx: (Math.random() - 0.5) * 0.3, vy: (Math.random() - 0.5) * 0.3, r: Math.random() * 1.6 + 0.7 };
    }
    function resize() {
      var r = el.getBoundingClientRect();
      W = Math.max(1, r.width); H = Math.max(1, r.height);
      el.width = Math.round(W * dpr); el.height = Math.round(H * dpr);
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      var target = Math.max(30, Math.min(120, Math.round((W * H) / 15000)));
      while (nodes.length < target) nodes.push(mk());
      nodes.length = target;
    }
    function draw(step) {
      var i, j, n, a, b, dx, dy, d2, al, dm, dxm, dym;
      ctx.clearRect(0, 0, W, H);
      for (i = 0; i < nodes.length; i++) {
        n = nodes[i];
        if (!step) continue;
        dxm = mouse.x - n.x; dym = mouse.y - n.y;
        dm = Math.sqrt(dxm * dxm + dym * dym);
        if (dm < MR && dm > 1) { n.vx += (dxm / dm) * 0.012; n.vy += (dym / dm) * 0.012; }
        n.vx *= 0.992; n.vy *= 0.992;
        if (Math.sqrt(n.vx * n.vx + n.vy * n.vy) < 0.08) { n.vx += (Math.random() - 0.5) * 0.05; n.vy += (Math.random() - 0.5) * 0.05; }
        n.x += n.vx; n.y += n.vy;
        if (n.x < 0 || n.x > W) n.vx *= -1;
        if (n.y < 0 || n.y > H) n.vy *= -1;
        n.x = Math.max(0, Math.min(W, n.x)); n.y = Math.max(0, Math.min(H, n.y));
      }
      ctx.lineWidth = 1;
      for (i = 0; i < nodes.length; i++) {
        a = nodes[i];
        for (j = i + 1; j < nodes.length; j++) {
          b = nodes[j];
          dx = a.x - b.x; dy = a.y - b.y; d2 = dx * dx + dy * dy;
          if (d2 < LINK * LINK) {
            al = (1 - Math.sqrt(d2) / LINK) * 0.32;
            ctx.strokeStyle = 'rgba(0,229,255,' + al.toFixed(3) + ')';
            ctx.beginPath(); ctx.moveTo(a.x, a.y); ctx.lineTo(b.x, b.y); ctx.stroke();
            if (step && packets.length < 26 && Math.random() < 0.0009) {
              packets.push({ a: a, b: b, t: 0, s: 0.008 + Math.random() * 0.014, c: pcols[(Math.random() * pcols.length) | 0] });
            }
          }
        }
        dxm = a.x - mouse.x; dym = a.y - mouse.y; d2 = dxm * dxm + dym * dym;
        if (d2 < MR * MR) {
          al = (1 - Math.sqrt(d2) / MR) * 0.55;
          ctx.strokeStyle = 'rgba(0,255,135,' + al.toFixed(3) + ')';
          ctx.beginPath(); ctx.moveTo(a.x, a.y); ctx.lineTo(mouse.x, mouse.y); ctx.stroke();
        }
      }
      for (i = packets.length - 1; i >= 0; i--) {
        var p = packets[i];
        if (step) p.t += p.s;
        if (p.t >= 1) { packets.splice(i, 1); continue; }
        var x = p.a.x + (p.b.x - p.a.x) * p.t, y = p.a.y + (p.b.y - p.a.y) * p.t;
        ctx.shadowColor = p.c; ctx.shadowBlur = 12; ctx.fillStyle = p.c;
        ctx.beginPath(); ctx.arc(x, y, 2.2, 0, Math.PI * 2); ctx.fill();
        ctx.shadowBlur = 0;
      }
      ctx.fillStyle = 'rgba(160,240,255,.75)';
      for (i = 0; i < nodes.length; i++) {
        n = nodes[i];
        ctx.beginPath(); ctx.arc(n.x, n.y, n.r, 0, Math.PI * 2); ctx.fill();
      }
    }
    function loop() {
      raf = 0;
      if (!visible || document.hidden) return;
      draw(true);
      raf = requestAnimationFrame(loop);
    }
    function start() { if (!raf && !reduce) raf = requestAnimationFrame(loop); }

    resize();
    if ('ResizeObserver' in window) new ResizeObserver(function () { resize(); if (reduce) draw(false); }).observe(el);
    else window.addEventListener('resize', resize);
    window.addEventListener('pointermove', function (ev) {
      var r = el.getBoundingClientRect();
      mouse.x = ev.clientX - r.left; mouse.y = ev.clientY - r.top;
    }, { passive: true });
    document.addEventListener('pointerleave', function () { mouse.x = -9999; mouse.y = -9999; });
    document.addEventListener('visibilitychange', start);
    if ('IntersectionObserver' in window) {
      new IntersectionObserver(function (en) { visible = en[0].isIntersecting; start(); }).observe(el);
    }
    if (reduce) draw(false); else start();
  }

  /* ---------- Terminal que se escribe sola ---------- */
  var term = document.getElementById('term');
  if (term) initTerm(term);

  function initTerm(termEl) {
    var SCRIPTS = [
      { key: 'god', tag: 'GOD', ctx: 'diego@kali ~/proyectos', title: 'URB GOD MODE — zsh',
        hud: [['CPU', '14%'], ['RAM', '3.2G'], ['IP', '192.168.56.101'], ['VPN', 'tun0'], ['git', 'main'], ['', '10:42']],
        entries: [
          { k: 'cmd', t: 'urb doctor' },
          { k: 'out', t: '  ✔ bash   ✔ tmux   ✔ zsh   ✔ nmap   ✔ fzf   ✔ figlet', c: 'ok', d: 160 },
          { k: 'out', t: '  Todo listo. Ningún dotfile modificado.', c: 'dim', d: 420 },
          { k: 'cmd', t: 'urb network' },
          { k: 'out', t: '  IFACE   eth0   192.168.56.101/24', d: 90 },
          { k: 'out', t: '  GW      192.168.56.1', d: 90 },
          { k: 'out', t: '  VPN     ● ACTIVE  tun0  10.10.14.7', c: 'ok', d: 420 },
          { k: 'cmd', t: 'urb sessions' },
          { k: 'out', t: '  PROFILE  SESSION          STATE', c: 'head', d: 90 },
          { k: 'out', t: '  GOD      god-4121-08812   attached', d: 90 },
          { k: 'out', t: '  RED      red-3990-17345   detached', d: 90 },
          { k: 'out', t: '  BLUE     —                none', c: 'dim', d: 90 }
        ] },
      { key: 'red', tag: 'RED', ctx: 'htb-lame ▸ 10.10.10.3', title: 'URB RED — htb-lame',
        hud: [['LAB', 'htb-lame'], ['TGT', '10.10.10.3'], ['VPN', 'tun0 10.10.14.7'], ['CPU', '21%'], ['RAM', '3.4G']],
        entries: [
          { k: 'cmd', t: 'lab new htb-lame --target 10.10.10.3' },
          { k: 'out', t: '  ✔ Laboratorio htb-lame creado y seleccionado', c: 'ok', d: 380 },
          { k: 'cmd', t: 'recon initial' },
          { k: 'out', t: '  lab htb-lame (directorio actual) · objetivo 10.10.10.3', c: 'dim', d: 160 },
          { k: 'prog', t: '  nmap -sV -T4 --open', d: 1950 },
          { k: 'out', t: '  PORT      STATE  SERVICE      VERSION', c: 'head', d: 120 },
          { k: 'out', t: '  21/tcp    open   ftp          vsftpd 2.3.4', d: 110 },
          { k: 'out', t: '  22/tcp    open   ssh          OpenSSH 4.7p1 Debian 8ubuntu1', d: 110 },
          { k: 'out', t: '  139/tcp   open   netbios-ssn  Samba smbd 3.X - 4.X', d: 110 },
          { k: 'out', t: '  445/tcp   open   netbios-ssn  Samba smbd 3.0.20-Debian', d: 160 },
          { k: 'out', t: '  ✔ S-001 complete · resultados en scans/', c: 'ok', d: 400 },
          { k: 'cmd', t: 'findings add "FTP anonymous" --status suspected' },
          { k: 'out', t: '  ✔ F-001 · FTP anonymous · suspected', c: 'ok', d: 100 }
        ] },
      { key: 'blue', tag: 'BLUE', ctx: 'ws incident-rdp', title: 'URB BLUE — incident-rdp',
        hud: [['WS', 'incident-rdp'], ['DB', 'SQLite'], ['MODE', 'offline'], ['CPU', '9%'], ['RAM', '2.9G']],
        entries: [
          { k: 'cmd', t: 'ingest windows ./export/security.csv --tz +01:00' },
          { k: 'out', t: '  ✔ Fuente importada · sha256 9f2c…e41a · copia de solo lectura', c: 'ok', d: 420 },
          { k: 'cmd', t: 'detect run --threshold 5 --window 600' },
          { k: 'out', t: '  ID     RULE   COUNT  SOURCE IP       WINDOW', c: 'head', d: 120 },
          { k: 'out', t: '  A-001  4625   27     203.0.113.50    10:02:11 → 10:09:48', c: 'warn', d: 420 },
          { k: 'cmd', t: 'alerts status A-001 investigating' },
          { k: 'out', t: '  ✔ A-001 → investigating', c: 'ok', d: 380 },
          { k: 'cmd', t: 'cases new "Fuerza bruta RDP desde 203.0.113.50"' },
          { k: 'out', t: '  ✔ C-001 creado', c: 'ok', d: 320 },
          { k: 'cmd', t: 'cases link C-001 --alert A-001' },
          { k: 'out', t: '  ✔ C-001 ← A-001 · historial actualizado', c: 'ok', d: 100 }
        ] }
    ];

    var body = document.getElementById('tbody');
    var hud = document.getElementById('thud');
    var title = document.getElementById('ttitle');
    var count = document.getElementById('tcount');
    var si = 1, ei = 0, ch = 0, timer = 0, typingSpan = null, caretEl = null;

    function span(cls, text) {
      var s = document.createElement('span');
      if (cls) s.className = cls;
      if (text !== undefined) s.textContent = text;
      return s;
    }
    function dropCaret() { if (caretEl && caretEl.parentNode) caretEl.parentNode.removeChild(caretEl); caretEl = null; }
    function line(cls) { var d = document.createElement('div'); d.className = 'tl' + (cls ? ' ' + cls : ''); body.appendChild(d); return d; }
    function promptLine(sc) {
      var d = line('hi');
      d.appendChild(span('ptag', sc.tag));
      d.appendChild(span('pctx', sc.ctx + ' '));
      d.appendChild(span('parr', '❯ '));
      return d;
    }
    function appendEntry(sc, e, full) {
      dropCaret();
      if (e.k === 'cmd') {
        var d = promptLine(sc);
        typingSpan = span('', full ? e.t : '');
        d.appendChild(typingSpan);
        if (!full) { caretEl = span('caret'); d.appendChild(caretEl); }
      } else if (e.k === 'prog') {
        var p = line('dim');
        var wrap = span('prog');
        wrap.appendChild(span('', e.t));
        wrap.appendChild(span('pbar'));
        p.appendChild(wrap);
      } else {
        line(e.c || '').textContent = e.t;
      }
    }
    function finalPrompt(sc) {
      dropCaret();
      var d = promptLine(sc);
      caretEl = span('caret');
      d.appendChild(caretEl);
    }
    function setupScript() {
      var sc = SCRIPTS[si];
      termEl.className = 'term tilt t-' + sc.key;
      title.textContent = sc.title;
      count.textContent = (si + 1) + ' / ' + SCRIPTS.length;
      hud.textContent = '';
      hud.appendChild(span('hudtag', sc.tag));
      sc.hud.forEach(function (h) {
        var s = span('', h[0] ? h[0] + ' ' : '');
        var b = document.createElement('b'); b.textContent = h[1];
        s.appendChild(b);
        hud.appendChild(s);
      });
      body.textContent = '';
      typingSpan = null; caretEl = null; ei = 0; ch = 0;
    }
    function renderFull() {
      setupScript();
      var sc = SCRIPTS[si];
      sc.entries.forEach(function (e) { appendEntry(sc, e, true); });
      finalPrompt(sc);
    }
    function tick() {
      var sc = SCRIPTS[si];
      var e = sc.entries[ei];
      if (!e) {
        timer = setTimeout(function () {
          si = (si + 1) % SCRIPTS.length;
          setupScript();
          appendEntry(SCRIPTS[si], SCRIPTS[si].entries[0], false);
          timer = setTimeout(tick, 600);
        }, 3400);
        return;
      }
      if (e.k === 'cmd' && ch < e.t.length) {
        ch++;
        typingSpan.textContent = e.t.slice(0, ch);
        timer = setTimeout(tick, 24 + Math.random() * 46);
        return;
      }
      ei++; ch = 0;
      var next = sc.entries[ei];
      if (next) appendEntry(sc, next, false); else finalPrompt(sc);
      timer = setTimeout(tick, !next ? 0 : (next.k === 'cmd' ? 520 : (next.d || 100)));
    }

    if (reduce) {
      renderFull();
      setInterval(function () { si = (si + 1) % SCRIPTS.length; renderFull(); }, 7000);
    } else {
      setupScript();
      appendEntry(SCRIPTS[si], SCRIPTS[si].entries[0], false);
      timer = setTimeout(tick, 900);
    }
  }

  /* ---------- Pestañas de entornos ---------- */
  var tabsRoot = document.querySelector('[data-tabs]');
  if (tabsRoot) initTabs(tabsRoot);

  function initTabs(root) {
    var tabs = Array.prototype.slice.call(root.querySelectorAll('[data-mode]'));
    var panels = Array.prototype.slice.call(root.querySelectorAll('[data-panel]'));
    var keys = tabs.map(function (t) { return t.getAttribute('data-mode'); });
    var cur = 0, auto = true;

    function show(i, held) {
      cur = i;
      root.className = root.className.replace(/\bm-\w+/, 'm-' + keys[i]);
      tabs.forEach(function (t, j) {
        var on = j === i;
        t.classList.toggle('is-on', on);
        t.classList.toggle('is-held', on && held);
        t.setAttribute('aria-pressed', on ? 'true' : 'false');
      });
      panels.forEach(function (p) { p.hidden = p.getAttribute('data-panel') !== keys[i]; });
    }
    tabs.forEach(function (t, i) {
      t.addEventListener('click', function () { auto = false; show(i, true); });
    });
    show(0, false);
    if (!reduce) {
      setInterval(function () { if (auto) show((cur + 1) % tabs.length, false); }, 7000);
    }
  }
})();
