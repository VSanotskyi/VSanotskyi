#!/usr/bin/env bash
# Aggregate languages from all owned repos (public + private) and write assets/top-langs.svg
set -euo pipefail
cd "$(dirname "$0")/.."

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

gh api user/repos --paginate --jq '.[] | select(.owner.login=="VSanotskyi" and .fork==false) | .name' \
| while read -r name; do
  gh api "repos/VSanotskyi/$name/languages" --jq 'to_entries[] | [.key, .value] | @tsv' 2>/dev/null || true
done > "$TMP"

python3 - "$TMP" <<'PY'
import sys
from pathlib import Path
from collections import defaultdict

bytes_by_lang = defaultdict(int)
with open(sys.argv[1]) as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        lang, n = line.split("\t")
        bytes_by_lang[lang] += int(n)

# Skip tiny infra noise in the bar; keep top product languages
skip = {"Dockerfile", "Shell", "Makefile"}
items = sorted(
    ((k, v) for k, v in bytes_by_lang.items() if k not in skip),
    key=lambda x: x[1],
    reverse=True,
)[:5]

colors = {
    "TypeScript": "#3178c6",
    "JavaScript": "#f1e05a",
    "HTML": "#e34c26",
    "CSS": "#563d7c",
    "SCSS": "#c6538c",
    "Python": "#3572A5",
    "Go": "#00ADD8",
    "Rust": "#dea584",
    "Java": "#b07219",
    "Vue": "#41b883",
}

total = sum(v for _, v in items) or 1
width, padding = 860, 24
bar_y, bar_h = 70, 10
legend_y, row_h = 100, 28
height = legend_y + row_h * len(items) + padding

x = padding
bar_w = width - padding * 2
segs = []
for lang, n in items:
    w = bar_w * (n / total)
    segs.append((x, w, colors.get(lang, "#8b949e")))
    x += w

seg_svg = "\n  ".join(
    f'<rect x="{sx:.2f}" y="{bar_y}" width="{sw:.2f}" height="{bar_h}" fill="{c}"/>'
    for sx, sw, c in segs
)

legend = []
for i, (lang, n) in enumerate(items):
    y = legend_y + i * row_h
    pct = 100.0 * n / total
    color = colors.get(lang, "#8b949e")
    legend.append(
        f'<circle cx="{padding + 6}" cy="{y + 6}" r="6" fill="{color}"/>\n'
        f'  <text x="{padding + 22}" y="{y + 11}" fill="#c9d1d9" '
        f'font-family="Segoe UI, Ubuntu, Sans-Serif" font-size="14">{lang} {pct:.2f}%</text>'
    )

svg = f'''<svg width="{width}" height="{height}" viewBox="0 0 {width} {height}" fill="none" xmlns="http://www.w3.org/2000/svg" role="img" aria-labelledby="title">
  <title id="title">Most Used Languages</title>
  <rect width="{width}" height="{height}" rx="8" fill="#0d1117"/>
  <text x="{padding}" y="36" fill="#36BCF7" font-family="Segoe UI, Ubuntu, Sans-Serif" font-size="18" font-weight="600">Most Used Languages</text>
  <rect x="{padding}" y="{bar_y}" width="{bar_w}" height="{bar_h}" rx="5" fill="#21262d"/>
  {seg_svg}
  {chr(10).join("  " + line for line in legend)}
</svg>
'''
Path("assets/top-langs.svg").write_text(svg)
print("Updated assets/top-langs.svg")
for lang, n in items:
    print(f"  {lang}: {100.0 * n / total:.2f}%")
PY
