// Renders the streamed answer. Swift calls window.copilote.render(payload) at most once
// per frame; payload.segments come from ResponseSegmenter (Markdown and mermaid blocks).
(() => {
  'use strict';

  const scroller = document.getElementById('scroller');
  const empty = document.getElementById('empty');
  const answer = document.getElementById('answer');
  const notice = document.getElementById('notice');
  const tools = document.getElementById('answer-tools');
  // The whole answer as Markdown, once it is complete.
  let copyText = null;
  const native = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.copilote;
  const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');

  const escapeHtml = (text) => String(text).replace(/[&<>"']/g, (c) => (
    { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]
  ));

  // ---- Markdown -----------------------------------------------------------

  function codeBlock(text, lang) {
    const language = String(lang || '').trim().split(/\s+/)[0].toLowerCase();
    const body = language && hljs.getLanguage(language)
      ? hljs.highlight(text, { language, ignoreIllegals: true }).value
      : escapeHtml(text);
    return '<div class="code"><div class="code-bar"><span>' + escapeHtml(language || 'code') +
      '</span><button class="copy" type="button">Copy</button></div>' +
      '<pre><code class="hljs">' + body + '</code></pre></div>';
  }

  // Math: $…$, \(…\), $$…$$, \[…\]. KaTeX without `trust` (no \href, no HTML), errors shown in
  // place. "$5 and $10" stays text: a $ opens only before a non-space and closes only after one,
  // never right before a letter or digit ("$PATH:$HOME" stays text too).
  function math(tex, displayMode) {
    const html = katex.renderToString(tex.trim(), { displayMode, throwOnError: false, strict: 'ignore', errorColor: '#ff8a80' });
    return displayMode ? '<div class="math">' + html + '</div>' : html;
  }

  const mathBlock = {
    name: 'mathBlock',
    level: 'block',
    start(src) { const m = src.match(/^ {0,3}(?:\$\$|\\\[)/m); return m ? m.index : undefined; },
    tokenizer(src) {
      const m = /^ {0,3}\$\$([\s\S]+?)\$\$[ \t]*(?:\n|$)/.exec(src) || /^ {0,3}\\\[([\s\S]+?)\\\][ \t]*(?:\n|$)/.exec(src);
      if (m) return { type: 'mathBlock', raw: m[0], text: m[1] };
    },
    renderer(token) { return math(token.text, true); },
  };

  const mathInline = {
    name: 'mathInline',
    level: 'inline',
    start(src) { const m = src.match(/\$|\\\(|\\\[/); return m ? m.index : undefined; },
    tokenizer(src) {
      let m = /^\$\$([^$]+?)\$\$/.exec(src) || /^\\\[([\s\S]+?)\\\]/.exec(src);
      if (m) return { type: 'mathInline', raw: m[0], text: m[1], display: true };
      m = /^\\\(([\s\S]+?)\\\)/.exec(src) || /^\$(?!\s)((?:\\.|[^\\$\n])+?)(?<!\s)\$(?![A-Za-z0-9])/.exec(src);
      if (m) return { type: 'mathInline', raw: m[0], text: m[1], display: false };
    },
    renderer(token) { return math(token.text, token.display); },
  };

  marked.use({ extensions: [mathBlock, mathInline] });

  marked.use({
    gfm: true,
    renderer: {
      // Raw HTML from the model is shown as text, never interpreted.
      html(token) { return escapeHtml(token.raw || token.text || ''); },
      code(token) { return codeBlock(token.text, token.lang); },
    },
  });

  // ---- Mermaid (loaded lazily: 5 MB, only needed once a diagram shows up) ----

  let mermaidReady = null;
  function loadMermaid() {
    if (!mermaidReady) {
      mermaidReady = new Promise((resolve, reject) => {
        const script = document.createElement('script');
        script.src = 'vendor/mermaid.min.js';
        script.onload = () => {
          window.mermaid.initialize({
            startOnLoad: false,
            securityLevel: 'strict',
            theme: 'base',
            fontFamily: '-apple-system, BlinkMacSystemFont, system-ui, sans-serif',
            themeVariables: {
              darkMode: true,
              fontSize: '12px',
              background: '#1c1c22',
              primaryColor: '#2d2d3a',
              primaryTextColor: '#ececf1',
              primaryBorderColor: '#5f5f78',
              secondaryColor: '#262630',
              tertiaryColor: '#1f1f27',
              lineColor: '#8b8b9e',
              textColor: '#ececf1',
              edgeLabelBackground: '#1c1c22',
              clusterBkg: '#1f1f27',
              clusterBorder: '#3a3a48',
              noteBkgColor: '#2a2a35',
              noteTextColor: '#ececf1',
            },
          });
          resolve(window.mermaid);
        };
        script.onerror = () => reject(new Error('mermaid failed to load'));
        document.head.appendChild(script);
      });
    }
    return mermaidReady;
  }

  const diagramCache = new Map(); // source -> svg string, or null when invalid
  let renderCount = 0;
  let renderQueue = Promise.resolve();

  // mermaid.render is not re-entrant: diagrams render one after the other.
  function renderMermaid(source) {
    const run = async () => {
      const id = 'mmd-' + (++renderCount);
      try {
        const m = await loadMermaid();
        if (!(await m.parse(source, { suppressErrors: true }))) return null;
        const { svg } = await m.render(id, source);
        return svg;
      } catch (error) {
        return null;
      } finally {
        const leftover = document.getElementById('d' + id);
        if (leftover) leftover.remove();
      }
    };
    const result = renderQueue.then(run);
    renderQueue = result.catch(() => {});
    return result;
  }

  // Mermaid shrinks wide graphs to the panel width until labels are unreadable:
  // shrink at most to 70 %, and let anything wider scroll horizontally.
  function sizeDiagram(el) {
    const svg = el.querySelector('svg');
    if (!svg || !svg.viewBox || !svg.viewBox.baseVal || !svg.viewBox.baseVal.width) return;
    const natural = svg.viewBox.baseVal.width;
    const available = el.clientWidth - 24;
    const width = natural <= available ? natural : Math.max(available, natural * 0.7);
    svg.style.maxWidth = 'none';
    svg.style.width = width + 'px';
    svg.style.height = 'auto';
  }

  function applyDiagram(el, svg, source) {
    if (svg) {
      el.className = 'diagram';
      el.innerHTML = svg;
      stripTooltips(el);
      // No `title`: a tooltip is a system window, visible in a screen share.
      el.setAttribute('aria-label', 'Enlarge diagram');
      el.onclick = () => openZoom(el);
      sizeDiagram(el);
    } else {
      el.className = '';
      el.innerHTML = codeBlock(source, 'mermaid') + '<p class="diagram-note">Invalid diagram: source displayed.</p>';
    }
  }

  function renderDiagram(node, segment) {
    const key = (segment.complete ? 'done:' : 'wip:') + segment.source;
    if (node.key === key) return;
    node.key = key;
    if (!segment.complete) {
      node.el.className = 'diagram pending';
      node.el.textContent = 'Building diagram…';
      return;
    }
    if (diagramCache.has(segment.source)) {
      applyDiagram(node.el, diagramCache.get(segment.source), segment.source);
      return;
    }
    node.el.className = 'diagram pending';
    node.el.textContent = 'Diagram…';
    renderMermaid(segment.source).then((svg) => {
      diagramCache.set(segment.source, svg);
      if (node.key !== key) return;
      applyDiagram(node.el, svg, segment.source);
      if (pinned) scrollToBottom();
      updateFades();
    });
  }

  // ---- Diagram zoom: grows from the diagram, goes back to it --------------

  const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
  let zoom = null;

  function openZoom(el) {
    const svg = el.querySelector('svg');
    if (!svg || zoom) return;
    const from = el.getBoundingClientRect();
    zoom = document.createElement('div');
    zoom.className = 'zoom';
    const sheet = document.createElement('div');
    sheet.className = 'zoom-sheet';
    const copy = svg.cloneNode(true);
    const natural = svg.viewBox && svg.viewBox.baseVal ? svg.viewBox.baseVal.width : 0;
    copy.style.width = Math.max(natural, window.innerWidth - 32) + 'px';
    copy.style.maxWidth = 'none';
    copy.style.height = 'auto';
    sheet.appendChild(copy);
    zoom.appendChild(sheet);
    const hint = document.createElement('p');
    hint.className = 'zoom-hint';
    hint.textContent = 'Click to return';
    zoom.appendChild(hint);
    zoom.onclick = closeZoom;
    document.body.appendChild(zoom);
    if (!reduceMotion.matches) {
      const to = sheet.getBoundingClientRect();
      sheet.style.transformOrigin = 'top left';
      sheet.style.transform = `translate(${from.left - to.left}px, ${from.top - to.top}px) scale(${from.width / to.width})`;
      sheet.getBoundingClientRect();
      sheet.style.transition = 'transform 260ms cubic-bezier(0.2, 0.8, 0.2, 1)';
      sheet.style.transform = 'none';
    }
    requestAnimationFrame(() => zoom && zoom.classList.add('open'));
    zoom.origin = el;
  }

  function closeZoom() {
    if (!zoom) return;
    const leaving = zoom;
    zoom = null;
    const sheet = leaving.querySelector('.zoom-sheet');
    leaving.classList.remove('open');
    if (!reduceMotion.matches && leaving.origin) {
      const to = leaving.origin.getBoundingClientRect();
      const from = sheet.getBoundingClientRect();
      sheet.style.transition = 'transform 200ms cubic-bezier(0.4, 0, 0.8, 0.2)';
      sheet.style.transform = `translate(${to.left - from.left}px, ${to.top - from.top}px) scale(${to.width / from.width})`;
    }
    setTimeout(() => leaving.remove(), reduceMotion.matches ? 120 : 200);
  }

  document.addEventListener('keydown', (event) => { if (event.key === 'Escape') closeZoom(); });

  // ---- Rendering ----------------------------------------------------------

  let nodes = [];
  let currentAnswerId = null;
  let pending = null;
  let frame = 0;

  // `now`: render at once (copilote-render's off-screen page has no display, so no frames).
  function render(payload, now) {
    pending = payload;
    if (now) {
      if (frame) cancelAnimationFrame(frame);
      flush();
      return;
    }
    if (!frame) frame = requestAnimationFrame(flush);
  }

  function flush() {
    frame = 0;
    const payload = pending;
    pending = null;
    if (!payload) return;

    if (payload.answerId !== currentAnswerId) {
      currentAnswerId = payload.answerId;
      clearAnswer();
      answer.classList.remove('entering');
      void answer.offsetWidth; // restart the settle animation
      answer.classList.add('entering');
      pinned = true;
    }
    empty.hidden = true;
    answer.hidden = false;

    payload.segments.forEach((segment, index) => {
      let node = nodes[index];
      if (!node || node.kind !== segment.kind) {
        const el = document.createElement('div');
        if (node) answer.replaceChild(el, node.el); else answer.appendChild(el);
        node = nodes[index] = { kind: segment.kind, key: null, el };
      }
      if (segment.kind === 'markdown') {
        if (node.key !== segment.text) {
          node.el.innerHTML = marked.parse(segment.text);
          stripTooltips(node.el);
          node.key = segment.text;
        }
      } else {
        renderDiagram(node, segment);
      }
    });
    while (nodes.length > payload.segments.length) nodes.pop().el.remove();

    copyText = payload.copy || null;
    tools.hidden = !copyText;
    setNotice(payload.notice);
    if (pinned) scrollToBottom();
    updateFades();
  }

  function setNotice(value) {
    if (!value) { notice.hidden = true; return; }
    notice.hidden = false;
    notice.className = 'notice ' + (value.kind || '');
    notice.textContent = value.text;
    if (value.retry) {
      const button = document.createElement('button');
      button.type = 'button';
      button.className = 'copy retry';
      button.textContent = 'Retry';
      notice.append(' ', button);
    }
  }

  notice.addEventListener('click', (event) => {
    if (event.target.closest('.retry') && native) native.postMessage({ type: 'retry' });
  });

  function clearAnswer() {
    nodes = [];
    answer.innerHTML = '';
    copyText = null;
    tools.hidden = true;
  }

  function reset() {
    pending = null;
    currentAnswerId = null;
    clearAnswer();
    answer.hidden = true;
    notice.hidden = true;
    empty.hidden = false;
    scroller.scrollTop = 0;
    lastScrollTop = 0;
    pinned = true;
    updateFades();
  }

  // ---- Scrolling (⌘↑ / ⌘↓ from Swift, wheel from the user) -------------------

  // While pinned, a streaming answer keeps the latest line in view. Any upward scroll
  // (⌘↑ or wheel) unpins; scrolling back down to the very bottom pins again.
  let pinned = true;
  let lastScrollTop = 0;

  function isAtBottom() {
    return scroller.scrollTop + scroller.clientHeight >= scroller.scrollHeight - 4;
  }

  function scrollToBottom() {
    scroller.scrollTop = scroller.scrollHeight;
  }

  function scrollPage(direction) {
    if (direction < 0) pinned = false;
    scroller.scrollBy({
      top: direction * scroller.clientHeight * 0.7,
      behavior: reducedMotion.matches ? 'auto' : 'smooth',
    });
  }

  function updateFades() {
    scroller.classList.toggle('fade-top', scroller.scrollTop > 2);
    scroller.classList.toggle('fade-bottom', scroller.scrollTop + scroller.clientHeight < scroller.scrollHeight - 2);
  }
  scroller.addEventListener('scroll', () => {
    const top = scroller.scrollTop;
    if (top < lastScrollTop - 1) pinned = false;
    else if (top > lastScrollTop && isAtBottom()) pinned = true;
    lastScrollTop = top;
    updateFades();
  }, { passive: true });
  window.addEventListener('resize', () => {
    answer.querySelectorAll('.diagram').forEach(sizeDiagram);
    updateFades();
  });

  // ---- Interactions ---------------------------------------------------------

  // The label is kept once, so a second click within the second does not keep « Copied » for good.
  function copyAndConfirm(button, text) {
    if (!native) return;
    const label = button.dataset.label || (button.dataset.label = button.textContent);
    native.postMessage({ type: 'copy', text });
    button.textContent = 'Copied';
    button.classList.add('done');
    clearTimeout(button.restoreTimer);
    button.restoreTimer = setTimeout(() => { button.textContent = label; button.classList.remove('done'); }, 1200);
  }

  // A context menu, a tooltip or a drag image is a system window, visible in a screen share: none
  // on the overlay. Tooltips come from `title` (KaTeX errors, Markdown link titles) and from an
  // SVG's <title> (Mermaid's accTitle).
  document.addEventListener('contextmenu', (event) => event.preventDefault());
  document.addEventListener('dragstart', (event) => event.preventDefault());

  function stripTooltips(root) {
    root.querySelectorAll('[title]').forEach((el) => el.removeAttribute('title'));
    root.querySelectorAll('svg title').forEach((el) => el.remove());
  }

  answer.addEventListener('click', (event) => {
    const link = event.target.closest('a');
    if (link) { event.preventDefault(); if (native && link.href.startsWith('https://')) native.postMessage({ type: 'openSource', url: link.href }); return; }
    const button = event.target.closest('.copy');
    if (button) copyAndConfirm(button, button.closest('.code').querySelector('code').textContent);
  });

  tools.addEventListener('click', (event) => {
    const button = event.target.closest('.copy');
    if (button && copyText) copyAndConfirm(button, copyText);
  });

  // Empty-state hints, with the shortcuts as configured in the app.
  function setHints(hints) {
    const list = empty.querySelector('.hints');
    list.innerHTML = '';
    hints.forEach(({ keys, label }) => {
      const term = document.createElement('dt');
      const key = document.createElement('kbd');
      key.textContent = keys;
      term.appendChild(key);
      const description = document.createElement('dd');
      description.textContent = label;
      list.append(term, description);
    });
  }

  window.copilote = { render, reset, scrollPage, setHints };
  setTimeout(() => { loadMermaid().catch(() => {}); }, 1500);
  if (native) native.postMessage({ type: 'ready' });
})();
