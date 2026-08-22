import sys

from pyfiglet import Figlet


def render_centered(text, font):
  figlet = Figlet(font=font, width=1000, justify="left")
  blocks = []
  canvas_width = 0

  for source_line in text.split("\n"):
    rendered = figlet.renderText(source_line).rstrip("\n")
    lines = [line.rstrip() for line in rendered.splitlines()]
    if not lines:
      lines = [""] * max(1, figlet.Font.height)

    block_width = max(map(len, lines), default=0)
    canvas_width = max(canvas_width, block_width)
    blocks.append((lines, block_width))

  centered_lines = []
  for lines, block_width in blocks:
    padding = " " * ((canvas_width - block_width) // 2)
    centered_lines.extend(padding + line if line else "" for line in lines)

  return "\n".join(centered_lines).rstrip() + "\n"


if __name__ == "__main__":
  sys.stdout.write(render_centered(sys.argv[1], sys.argv[2]))
