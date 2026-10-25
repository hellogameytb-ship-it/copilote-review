// One diagram per call: window.copiloteDiagram(source) renders it and returns its size, or
// throws when Mermaid rejects it (the indexer then keeps the fiche without a diagram).
(function () {
  'use strict';
  window.mermaid.initialize({
    startOnLoad: false,
    securityLevel: 'strict',
    theme: 'base',
    fontFamily: '-apple-system, BlinkMacSystemFont, system-ui, sans-serif',
    flowchart: { useMaxWidth: false },
    themeVariables: {
      darkMode: true,
      fontSize: '14px',
      background: '#1c1c22',
      primaryColor: '#2d2d3a',
      primaryTextColor: '#ececf1',
      primaryBorderColor: '#7b73d9',
      secondaryColor: '#262630',
      tertiaryColor: '#1f1f27',
      lineColor: '#8b8b9e',
      textColor: '#ececf1',
      edgeLabelBackground: '#1c1c22',
      clusterBkg: '#1f1f27',
      clusterBorder: '#3a3a48',
    },
  });

  let count = 0;
  window.copiloteDiagram = async function (source) {
    count += 1;
    const out = document.getElementById('out');
    out.innerHTML = '';
    const { svg } = await window.mermaid.render('diagram-' + count, source);
    out.innerHTML = svg;
    const box = out.getBoundingClientRect();
    return { width: Math.ceil(box.width), height: Math.ceil(box.height) };
  };
})();
