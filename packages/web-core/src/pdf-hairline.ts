import type { PathSegment } from "@open-document/wasm/abi/drawing";

/** Rasterize a solid zero-width stroke as device-pixel spans. */
export function pdfHairline(
  context: CanvasRenderingContext2D,
  segments: PathSegment[],
  matrix: DOMMatrix,
): boolean {
  // shortcut: curves, dashes and translucent strokes retain Canvas coverage until independently verified.
  if (
    segments.length > 8192 ||
    context.globalAlpha !== 1 ||
    context.globalCompositeOperation !== "source-over" ||
    context.getLineDash().length ||
    !(matrix.a * matrix.d - matrix.b * matrix.c)
  )
    return false;
  const path = new Path2D();
  const { width, height } = context.canvas;
  let rows = 0;
  let start: DOMPoint | undefined;
  let previous: DOMPoint | undefined;
  for (const segment of segments) {
    if (segment.op === "cubic") return false;
    if (segment.op === "close" && previous === start) continue;
    const next =
      segment.op === "close"
        ? start
        : matrix.transformPoint({ x: segment.x, y: segment.y });
    if (!next || !Number.isFinite(next.x) || !Number.isFinite(next.y))
      return false;
    if (segment.op === "move" || !previous) {
      start = previous = next;
      continue;
    }
    const [a, b] = previous.y <= next.y ? [previous, next] : [next, previous];
    previous = next;
    const first = Math.floor(a.y),
      last = Math.floor(b.y);
    const top = Math.max(0, first),
      bottom = Math.min(height - 1, last);
    if (top > bottom) continue;
    // shortcut: large paths retain Canvas coverage to bound generated spans.
    if ((rows += bottom - top + 1) > 8192) return false;
    const dx = b.x - a.x,
      dy = b.y - a.y;
    if (!Number.isFinite(dx) || !Number.isFinite(dy)) return false;
    const xAt = (y: number) => Math.floor(a.x + dx * ((y - a.y) / dy));
    for (let row = top; row <= bottom; row++) {
      const entry = row === first ? Math.floor(a.x) : xAt(row);
      const exit = row === last ? Math.floor(b.x) : xAt(row + 1);
      // Leave the crossing to the next row when that row is visible.
      const end = row < bottom && entry !== exit ? exit - Math.sign(dx) : exit;
      const left = Math.max(0, Math.min(entry, end));
      const right = Math.min(width - 1, Math.max(entry, end));
      if (left <= right) path.rect(left, row, right - left + 1, 1);
    }
  }
  context.save();
  try {
    context.resetTransform();
    context.fillStyle = context.strokeStyle;
    context.fill(path);
  } finally {
    context.restore();
  }
  return true;
}
