import type { DrawCommand, PathSegment } from "@open-document/wasm/abi/drawing";
import { aligned, pixelEdges, pixelRectangleStroke } from "./pdf-pixels.js";

type StrokePoint = { x: number; y: number };
type StrokeContour = { points: StrokePoint[]; closed: boolean };

function strokeCurve(matrix: DOMMatrix, line: (point: StrokePoint) => boolean) {
  const midpoint = (a: StrokePoint, b: StrokePoint): StrokePoint => ({
    x: (a.x + b.x) / 2,
    y: (a.y + b.y) / 2,
  });
  const curve = (
    a: StrokePoint,
    b: StrokePoint,
    c: StrokePoint,
    d: StrokePoint,
    depth: number,
  ): boolean => {
    const center = matrix.transformPoint(midpoint(a, d));
    const distance = (point: StrokePoint) => {
      const device = matrix.transformPoint(point);
      return (device.x - center.x) ** 2 + (device.y - center.y) ** 2;
    };
    if (depth === 10 || (distance(b) <= 1 && distance(c) <= 1)) return line(d);
    const ab = midpoint(a, b),
      bc = midpoint(b, c),
      cd = midpoint(c, d);
    const left = midpoint(ab, bc),
      right = midpoint(bc, cd),
      middle = midpoint(left, right);
    return (
      curve(a, ab, left, middle, depth + 1) &&
      curve(middle, right, cd, d, depth + 1)
    );
  };
  return curve;
}

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

/** Hint outline edges and straight caps independently in device pixels. */
export function pdfStroke(
  context: CanvasRenderingContext2D,
  command: Extract<DrawCommand, { op: "path" }>,
): boolean {
  // shortcut: connected or dashed paths use Canvas; extend when a native comparison fails.
  if (
    !command.path.length ||
    command.path.length % 2 ||
    command.lineWidth <= 0 ||
    context.getLineDash().length
  )
    return false;
  const matrix = context.getTransform();
  if (!aligned(matrix)) return false;
  const determinant = matrix.a * matrix.d - matrix.b * matrix.c;
  if (!determinant || !Number.isFinite(determinant)) return false;
  const round = context.lineCap === "round";
  const path = new Path2D();
  for (let index = 0; index < command.path.length; index += 2) {
    const start = command.path[index],
      end = command.path[index + 1];
    if (start?.op !== "move" || end?.op !== "line") return false;
    const a = matrix.transformPoint(new DOMPoint(start.x, start.y));
    const b = matrix.transformPoint(new DOMPoint(end.x, end.y));
    if (a.x !== b.x && a.y !== b.y) return false;
    const localLength = Math.hypot(end.x - start.x, end.y - start.y);
    const deviceLength = Math.hypot(b.x - a.x, b.y - a.y);
    if (!localLength || !deviceLength) return false;
    const width =
      (command.lineWidth * Math.abs(determinant) * localLength) / deviceLength;
    const cap =
      context.lineCap === "butt"
        ? 0
        : (command.lineWidth * deviceLength) / localLength / 2;
    const rect =
      a.x === b.x
        ? [
            a.x - width / 2,
            Math.min(a.y, b.y) - cap,
            a.x + width / 2,
            Math.max(a.y, b.y) + cap,
          ]
        : [
            Math.min(a.x, b.x) - cap,
            a.y - width / 2,
            Math.max(a.x, b.x) + cap,
            a.y + width / 2,
          ];
    if (!rect.every(Number.isFinite)) return false;
    const [x0, x1] =
      a.x === b.x || context.lineCap === "square"
        ? pixelEdges(rect[0]!, rect[2]!, true)
        : round
          ? [rect[0]!, rect[2]!]
          : [Math.round(rect[0]!), Math.round(rect[2]!)];
    const [y0, y1] =
      a.y === b.y || context.lineCap === "square"
        ? pixelEdges(rect[1]!, rect[3]!, true)
        : round
          ? [rect[1]!, rect[3]!]
          : [Math.round(rect[1]!), Math.round(rect[3]!)];
    if (round) {
      path.roundRect(
        x0,
        y0,
        x1 - x0,
        y1 - y0,
        a.x === b.x
          ? { x: (x1 - x0) / 2, y: cap }
          : { x: cap, y: (y1 - y0) / 2 },
      );
    } else path.rect(x0, y0, x1 - x0, y1 - y0);
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

function pathStrokeOutline(
  context: CanvasRenderingContext2D,
  contours: StrokeContour[],
  coveragePixels: number | null,
  fallbackToFill: boolean,
): boolean {
  if (
    context.lineCap !== "butt" ||
    context.lineJoin !== "miter" ||
    context.getLineDash().length
  )
    return false;
  const path = new Path2D();
  let count = 0;
  const polygon = (points: StrokePoint[]): boolean => {
    // shortcut: larger outlines use Canvas widening; extend for a failing native case.
    if ((count += points.length + 1) > 8192) return false;
    const area = points.reduce((sum, p, i) => {
      const next = points[(i + 1) % points.length]!;
      return sum + p.x * next.y - p.y * next.x;
    }, 0);
    // Preserve the native subpath origin while correcting winding.
    if (area < 0) points = [points[0]!, ...points.slice(1).reverse()];
    points.forEach((p, i) => {
      if (i) path.lineTo(p.x, p.y);
      else path.moveTo(p.x, p.y);
    });
    path.closePath();
    return true;
  };
  const direction = (a: StrokePoint, b: StrokePoint): StrokePoint => {
    const length = Math.hypot(b.x - a.x, b.y - a.y);
    return { x: (b.x - a.x) / length, y: (b.y - a.y) / length };
  };
  const radius = context.lineWidth / 2;
  for (const contour of contours) {
    const points = contour.points.filter(
      (p, i, all) => !i || p.x !== all[i - 1]!.x || p.y !== all[i - 1]!.y,
    );
    if (
      contour.closed &&
      points.length > 1 &&
      points.at(-1)!.x === points[0]!.x &&
      points.at(-1)!.y === points[0]!.y
    )
      points.pop();
    if (points.length < 2) continue;
    const edges = points.length - (contour.closed ? 0 : 1);
    for (let i = 0; i < edges; i++) {
      const a = points[i]!,
        b = points[(i + 1) % points.length]!,
        v = direction(a, b);
      const nx = -v.y * radius,
        ny = v.x * radius;
      if (
        !polygon([
          { x: a.x + nx, y: a.y + ny },
          { x: a.x - nx, y: a.y - ny },
          { x: b.x - nx, y: b.y - ny },
          { x: b.x + nx, y: b.y + ny },
        ])
      )
        return false;
    }
    for (
      let i = contour.closed ? 0 : 1;
      i < (contour.closed ? points.length : points.length - 1);
      i++
    ) {
      const p = points[i]!,
        a = direction(points[(i + points.length - 1) % points.length]!, p),
        b = direction(p, points[(i + 1) % points.length]!);
      const cross = a.x * b.y - a.y * b.x;
      if (!cross) continue;
      const side = cross > 0 ? -radius : radius;
      const first = { x: -a.y * side, y: a.x * side },
        last = { x: -b.y * side, y: b.x * side };
      const divisor = 1 + a.x * b.x + a.y * b.y;
      const corner = {
        x: (first.x + last.x) / divisor,
        y: (first.y + last.y) / divisor,
      };
      const wedge = [p, { x: p.x + first.x, y: p.y + first.y }];
      // Native miters bevel near a reversed segment to avoid unstable intersections.
      if (
        divisor >= 0.0001 &&
        Math.hypot(corner.x, corner.y) <= radius * context.miterLimit
      )
        wedge.push({ x: p.x + corner.x, y: p.y + corner.y });
      wedge.push({ x: p.x + last.x, y: p.y + last.y });
      if (!polygon(wedge)) return false;
    }
  }
  if (coveragePixels !== null) {
    if (
      strokeCoverage(
        context,
        path,
        contours.map((c) => c.points),
        radius * context.miterLimit,
        context.getTransform(),
        { samples: 4194304, pixels: coveragePixels, inclusive: true },
      )
    )
      return true;
    if (!fallbackToFill) return false;
  }
  context.save();
  try {
    context.fillStyle = context.strokeStyle;
    context.fill(path);
  } finally {
    context.restore();
  }
  return true;
}

/** Native strokes share one outline; curves subdivide in device space. */
export function pdfPathStroke(
  context: CanvasRenderingContext2D,
  segments: PathSegment[],
  pdf: boolean,
  filled: boolean,
  availablePixels: number,
  hairline = false,
): boolean {
  if (segments.length > 8192 || segments[0]?.op !== "move") return false;
  const roundDashes =
    pdf &&
    context.lineCap === "round" &&
    context.lineJoin === "round" &&
    context.getLineDash().length > 0;
  const curves = segments.some((segment) => segment.op === "cubic");
  const filledCoverage =
    (filled || curves) &&
    (curves || pdf) &&
    context.globalAlpha === 1 &&
    context.globalCompositeOperation === "source-over" &&
    context.lineCap === "butt" &&
    context.lineJoin === "miter" &&
    !context.getLineDash().length;
  const filledLinear = filledCoverage && !curves;
  if (filled && !curves && !filledLinear) return false;
  if (!roundDashes && !curves && !filledLinear) {
    let start: StrokePoint = segments[0];
    for (const segment of segments) {
      if (segment.op === "move") start = segment;
      // shortcut: closed straight contours retain Canvas coverage; extend with independent polygon controls.
      if (
        segment.op === "close" ||
        (segment.op === "line" &&
          segment.x === start.x &&
          segment.y === start.y)
      )
        return false;
    }
  }
  const matrix = context.getTransform();
  const determinant = matrix.a * matrix.d - matrix.b * matrix.c;
  if (
    !determinant ||
    !Number.isFinite(determinant) ||
    ![matrix.a, matrix.b, matrix.c, matrix.d, matrix.e, matrix.f].every(
      Number.isFinite,
    )
  )
    return false;
  const path = new Path2D();
  const contours: StrokeContour[] = [];
  let active: StrokeContour = { points: [], closed: false };
  let current: StrokePoint = { x: 0, y: 0 },
    first = current;
  let count = 0;
  const line = (point: StrokePoint): boolean => {
    // shortcut: larger paths use Canvas subdivision; extend for a failing native case.
    if (++count > 8192) return false;
    if (!active.points.length) active.points.push(current);
    active.points.push(point);
    path.lineTo(point.x, point.y);
    return true;
  };
  const curve = strokeCurve(matrix, line);
  for (const segment of segments) {
    switch (segment.op) {
      case "move":
        if (++count > 8192) return false;
        if (active.points.length) contours.push(active);
        active = { points: [segment], closed: false };
        path.moveTo(segment.x, segment.y);
        current = first = segment;
        break;
      case "line":
        if (!line(segment)) return false;
        current = segment;
        break;
      case "cubic":
        if (
          !curve(
            current,
            { x: segment.x1, y: segment.y1 },
            { x: segment.x2, y: segment.y2 },
            segment,
            0,
          )
        )
          return false;
        current = segment;
        break;
      case "close":
        if (++count > 8192) return false;
        active.closed = true;
        if (active.points.length) contours.push(active);
        active = { points: [], closed: false };
        path.closePath();
        current = first;
    }
  }
  if (active.points.length) contours.push(active);
  if (roundDashes && roundDashStroke(context, contours, availablePixels))
    return true;
  if (pdf) {
    const flat = contours.flatMap<PathSegment>((contour) => [
      ...contour.points.map((point, index): PathSegment => ({
        op: index === 0 ? "move" : "line",
        x: point.x,
        y: point.y,
      })),
      ...(contour.closed ? [{ op: "close" as const }] : []),
    ]);
    if (hairline && pdfHairline(context, flat, matrix)) return true;
    if (
      pixelRectangleStroke(
        context,
        {
          op: "path",
          path: flat,
          fill: "",
          stroke: String(context.strokeStyle),
          lineWidth: context.lineWidth,
        },
        true,
      )
    )
      return true;
  }
  if (
    !pathStrokeOutline(
      context,
      contours,
      filledCoverage ? availablePixels : null,
      curves,
    )
  )
    context.stroke(path);
  return true;
}

function roundDashStroke(
  context: CanvasRenderingContext2D,
  contours: StrokeContour[],
  availablePixels: number,
): boolean {
  const dash = context.getLineDash(),
    phase = context.lineDashOffset;
  if (
    !dash.every((n) => Number.isFinite(n) && n > 0) ||
    !Number.isFinite(phase)
  )
    return false;
  const total = dash.reduce((a, b) => a + b, 0);
  if (!Number.isFinite(total) || total <= 0) return false;
  let offset = ((phase % total) + total) % total,
    firstIndex = 0;
  while (offset >= dash[firstIndex]!) {
    offset -= dash[firstIndex]!;
    firstIndex = (firstIndex + 1) % dash.length;
  }
  const pieces: StrokePoint[][] = [];
  let steps = 0;
  for (const contour of contours) {
    const first = contour.points[0];
    if (!first || contour.points.length < 2) return false;
    const last = contour.points.at(-1)!;
    const points =
      contour.closed && first.x === last.x && first.y === last.y
        ? contour.points.slice(0, -1)
        : contour.points;
    const pieceStart = pieces.length;
    let index = firstIndex,
      remaining = dash[index]! - offset,
      active = false;
    for (let i = 1; i < points.length + (contour.closed ? 1 : 0); i++) {
      const b = points[i % points.length]!;
      let a = points[i - 1]!,
        length = Math.hypot(b.x - a.x, b.y - a.y);
      while (length > 0) {
        if (++steps > 8192) return false;
        const step = Math.min(length, remaining);
        const end =
          step === length
            ? b
            : {
                x: a.x + ((b.x - a.x) * step) / length,
                y: a.y + ((b.y - a.y) * step) / length,
              };
        if (index % 2 === 0) {
          if (!active) {
            pieces.push([a]);
            active = true;
          }
          pieces.at(-1)!.push(end);
        }
        a = end;
        length -= step;
        remaining -= step;
        if (remaining <= 0) {
          index = (index + 1) % dash.length;
          remaining = dash[index]!;
          active = false;
        }
      }
    }
    if (contour.closed && pieces.length > pieceStart + 1) {
      const head = pieces[pieceStart]!,
        tail = pieces.at(-1)!;
      const a = head[0]!,
        b = tail.at(-1)!;
      if (a.x === first.x && a.y === first.y && b.x === a.x && b.y === a.y) {
        tail.push(...head.slice(1));
        pieces.splice(pieceStart, 1);
      }
    }
  }
  if (!pieces.length) return true;
  const pairs: PathSegment[] = [];
  let axes = true;
  for (const points of pieces)
    for (let i = 1; i < points.length; i++) {
      const a = points[i - 1]!,
        b = points[i]!;
      if (a.x !== b.x && a.y !== b.y) axes = false;
      if (a.x !== b.x || a.y !== b.y)
        pairs.push(
          { op: "move", x: a.x, y: a.y },
          { op: "line", x: b.x, y: b.y },
        );
    }
  if (axes && pairs.length) {
    context.save();
    try {
      context.setLineDash([]);
      context.lineDashOffset = 0;
      if (
        pdfStroke(context, {
          op: "path",
          path: pairs,
          fill: "",
          stroke: "000000",
          lineWidth: context.lineWidth,
        })
      )
        return true;
    } finally {
      context.restore();
    }
  }
  const outline = new Path2D(),
    radius = context.lineWidth / 2,
    matrix = context.getTransform();
  let budget = 0;
  const flatten = strokeCurve(matrix, (point) => {
    if (++budget > 8192) return false;
    outline.lineTo(point.x, point.y);
    return true;
  });
  for (const points of pieces) {
    for (let i = 1; i < points.length; i++) {
      const a = points[i - 1]!,
        b = points[i]!,
        length = Math.hypot(b.x - a.x, b.y - a.y);
      if (!length) continue;
      if ((budget += 5) > 8192) return false;
      const nx = (-(b.y - a.y) * radius) / length,
        ny = ((b.x - a.x) * radius) / length;
      outline.moveTo(a.x + nx, a.y + ny);
      outline.lineTo(a.x - nx, a.y - ny);
      outline.lineTo(b.x - nx, b.y - ny);
      outline.lineTo(b.x + nx, b.y + ny);
      outline.closePath();
    }
    for (const [index, point] of points.entries()) {
      if ((budget += 2) > 8192) return false;
      const neighbor = index === 0 ? points[1]! : points[index - 1]!;
      const dx = point.x - neighbor.x,
        dy = point.y - neighbor.y,
        length = Math.hypot(dx, dy);
      const ux = length ? dx / length : 1,
        uy = length ? dy / length : 0;
      const local = (x: number, y: number): StrokePoint => ({
        x: point.x + (x * ux - y * uy) * radius,
        y: point.y + (x * uy + y * ux) * radius,
      });
      const k = 0.55228475;
      const quarters = [
        [1, 0, 1, k, k, 1, 0, 1],
        [0, 1, -k, 1, -1, k, -1, 0],
        [-1, 0, -1, -k, -k, -1, 0, -1],
        [0, -1, k, -1, 1, -k, 1, 0],
      ];
      outline.moveTo(point.x + ux * radius, point.y + uy * radius);
      for (const q of quarters)
        if (
          !flatten(
            local(q[0]!, q[1]!),
            local(q[2]!, q[3]!),
            local(q[4]!, q[5]!),
            local(q[6]!, q[7]!),
            0,
          )
        )
          return false;
      outline.closePath();
    }
  }
  return strokeCoverage(context, outline, pieces, radius, matrix, {
    samples: 1048576,
    pixels: availablePixels,
    inclusive: false,
  });
}

export function strokeCoverage(
  context: CanvasRenderingContext2D,
  outline: Path2D,
  pieces: StrokePoint[][],
  radius: number,
  matrix: DOMMatrix,
  budget: { samples: number; pixels: number; inclusive: boolean },
  strokePath?: (samples: number) => Path2D,
): boolean {
  if (typeof context.strokeStyle !== "string") return false;
  let minX = Infinity,
    minY = Infinity,
    maxX = -Infinity,
    maxY = -Infinity;
  const rx = radius * Math.hypot(matrix.a, matrix.c),
    ry = radius * Math.hypot(matrix.b, matrix.d);
  for (const points of pieces)
    for (const p of points) {
      const q = matrix.transformPoint(p);
      minX = Math.min(minX, q.x - rx);
      maxX = Math.max(maxX, q.x + rx);
      minY = Math.min(minY, q.y - ry);
      maxY = Math.max(maxY, q.y + ry);
    }
  const left = Math.floor(minX) - 1,
    top = Math.floor(minY) - 1;
  const width = Math.ceil(maxX) + 1 - left,
    height = Math.ceil(maxY) + 1 - top;
  const area = width * height;
  const fits = (scale: number) =>
    width * scale <= 8192 &&
    height * scale <= 8192 &&
    area * scale ** 2 <= budget.samples &&
    area * (scale ** 2 + 1) <= budget.pixels;
  // shortcut: larger masks retain Canvas widening; extend only for a measured failing native flow.
  if (
    ![left, top, width, height].every(Number.isFinite) ||
    width <= 0 ||
    height <= 0 ||
    !Number.isSafeInteger(budget.pixels) ||
    !fits(4)
  )
    return false;
  const scale = strokePath && fits(8) ? 8 : 4;
  const sampleWidth = width * 4,
    sampleHeight = height * 4;
  const mask = document.createElement("canvas"),
    raster = document.createElement("canvas");
  mask.width = width * scale;
  mask.height = height * scale;
  raster.width = width;
  raster.height = height;
  try {
    const sample = mask.getContext("2d", { willReadFrequently: true }),
      output = raster.getContext("2d");
    if (!sample || !output) return false;
    const device = new Path2D();
    device.addPath(outline, matrix);
    sample.setTransform(4, 0, 0, 4, -left * 4, -top * 4);
    if (strokePath) {
      sample.setTransform(
        matrix.a * scale,
        matrix.b * scale,
        matrix.c * scale,
        matrix.d * scale,
        (matrix.e - left) * scale,
        (matrix.f - top) * scale,
      );
      sample.lineWidth = context.lineWidth;
      sample.lineJoin = context.lineJoin;
      sample.lineCap = context.lineCap;
      sample.miterLimit = context.miterLimit;
      sample.stroke(strokePath(width * height * 16));
    } else sample.fill(device);
    const pixels = sample.getImageData(0, 0, mask.width, mask.height).data;
    if (scale === 8) {
      // Skia can drop narrow corner coverage at 4x. Collapse the finer mask into the same cells.
      const stride = mask.width * 4;
      for (let y = 0; y < sampleHeight; y++)
        for (let x = 0; x < sampleWidth; x++) {
          const at = 2 * y * stride + x * 8 + 3;
          pixels[(y * sampleWidth + x) * 4 + 3] =
            pixels[at]! |
            pixels[at + 4]! |
            pixels[at + stride]! |
            pixels[at + stride + 4]!;
        }
    }
    const data = output.createImageData(width, height);
    const counts = new Uint8Array(area);
    for (let p = 0; p < area * 16; p++) {
      const offset = p * 4 + 3;
      if (!pixels[offset]) continue;
      const sx = p % sampleWidth,
        sy = Math.floor(p / sampleWidth);
      // Splash's inclusive upper bounds retain cells touched only at an edge.
      if (budget.inclusive)
        for (const [dx, dy] of [
          [1, 0],
          [0, 1],
          [1, 1],
        ] as const) {
          const x = sx + dx,
            y = sy + dy,
            at = (y * sampleWidth + x) * 4 + 3;
          if (
            x < sampleWidth &&
            y < sampleHeight &&
            !pixels[at] &&
            sample.isPointInPath(device, x, y)
          )
            pixels[at] = 1;
        }
      const at = (sy >>> 2) * width + (sx >>> 2);
      counts[at] = counts[at]! + 1;
    }
    const gamma = Uint8Array.from({ length: 17 }, (_, n) =>
      Math.round(255 * (n / 16) ** 1.5),
    );
    for (let p = 0; p < counts.length; p++)
      if (counts[p]) data.data[p * 4 + 3] = gamma[counts[p]!]!;
    output.putImageData(data, 0, 0);
    output.globalCompositeOperation = "source-in";
    output.fillStyle = context.strokeStyle;
    output.fillRect(0, 0, width, height);
    context.save();
    try {
      context.resetTransform();
      context.imageSmoothingEnabled = false;
      context.drawImage(raster, left, top);
    } finally {
      context.restore();
    }
  } finally {
    mask.width = mask.height = raster.width = raster.height = 0;
  }
  budget.samples -= area * scale ** 2;
  return true;
}
