import html
import multiprocessing
import os
import sys
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path

from render_text import render_centered


text = sys.argv[1]
preview_dir = Path(sys.argv[2])
catalog_path = Path(sys.argv[3])
catalog_entries = [
  (name, slug, render_font)
  for name, slug, render_font in (
    line.split("\t") for line in catalog_path.read_text().splitlines()
  )
]
catalog_entries = [
  entry for entry in catalog_entries
  if not (preview_dir / f"{entry[0].upper()}.svg").exists()
]

canvas_width = 768
canvas_height = 475
padding = 48


def render_preview(entry):
  name, _slug, font = entry
  try:
    rendered = render_centered(text, font).rstrip("\n")
  except Exception as error:
    return name, None, str(error)

  lines = rendered.splitlines() or [""]
  view_width = max(320, max(map(len, lines), default=0) * 12 + 96)
  view_height = max(180, len(lines) * 24 + 96)
  scale = min((canvas_width - 2 * padding) / view_width, (canvas_height - 2 * padding) / view_height)
  offset_x = (canvas_width - view_width * scale) / 2
  offset_y = (canvas_height - view_height * scale) / 2
  text_lines = []

  for index, line in enumerate(lines):
    y = 60 + index * 24
    text_lines.append(
      f'<text x="{padding}" y="{y}">{html.escape(line)}</text>'
    )

  svg = f'''<svg xmlns="http://www.w3.org/2000/svg" width="{canvas_width}" height="{canvas_height}" viewBox="0 0 {canvas_width} {canvas_height}">
  <rect width="100%" height="100%" fill="#000"/>
  <g transform="translate({offset_x:.4f} {offset_y:.4f}) scale({scale:.4f})">
    <g fill="#fff" font-family="monospace" font-size="20" xml:space="preserve">
      {''.join(text_lines)}
    </g>
  </g>
</svg>
'''
  return name, svg, ""


def write_previews(previews):
  failed = []
  for name, svg, error in previews:
    if svg is None:
      failed.append(f"{name}: {error}")
      continue

    target = preview_dir / f"{name.upper()}.svg"
    temporary = target.with_name(f".{target.name}.{os.getpid()}.tmp")
    temporary.write_text(svg)
    os.replace(temporary, target)

  if failed:
    print("Failed to render FIGlet previews:", file=sys.stderr)
    print("\n".join(failed), file=sys.stderr)
    raise SystemExit(1)


worker_count = min(8, len(catalog_entries), os.cpu_count() or 1)
if worker_count > 1:
  with ProcessPoolExecutor(
    max_workers=worker_count,
    mp_context=multiprocessing.get_context("fork"),
  ) as executor:
    write_previews(executor.map(render_preview, catalog_entries, chunksize=4))
else:
  write_previews(map(render_preview, catalog_entries))
