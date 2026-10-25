# Vendored libraries (no CDN at runtime)

| File | Package | Version | License |
|---|---|---|---|
| `marked.umd.js` | marked | 18.1.1 | MIT |
| `highlight.min.js` | @highlightjs/cdn-assets (common languages) | 11.12.0 | BSD-3-Clause |
| `mermaid.min.js` | mermaid (`dist/mermaid.min.js`) | 12.2.0 | MIT |
| `katex/` (`katex.min.js`, `katex.min.css`, `fonts/*.woff2`) | katex (`dist/`) | 0.16.47 | MIT |

Fetched from jsDelivr on 2026-10-19. Only change: the `sourceMappingURL` comment was
removed from `marked.umd.js` (the map is not shipped). Licenses are in `licenses/`.

To update: download the same paths for the new version, then check the overlay still
renders (Markdown, a fenced code block, a ```mermaid block).

KaTeX (added 2026-10-19) was copied from a local npm install of the same version; its CSS
keeps only the woff2 sources (the woff and ttf fallbacks are not shipped).
