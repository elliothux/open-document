import type { DrawCommand, PathSegment } from "@open-document/wasm/abi/drawing";

export function aligned(matrix: DOMMatrix): boolean {
  return (
    (matrix.b === 0 && matrix.c === 0) || (matrix.a === 0 && matrix.d === 0)
  );
}

export function pixelEdges(
  min: number,
  max: number,
  pdf = false,
): [number, number] {
  let first = Math.round(min),
    last = Math.round(max);
  if (first === last) {
    if (!pdf && min + max < first * 2) first--;
    else last++;
  }
  return [first, last];
}

function rectangleCorners(path: PathSegment[]): DOMPoint[] | undefined {
  if (path.length !== 5 || path[0]?.op !== "move") return undefined;
  const end = path[4];
  if (
    end?.op !== "close" &&
    !(end?.op === "line" && end.x === path[0].x && end.y === path[0].y)
  )
    return undefined;
  const points = [new DOMPoint(path[0].x, path[0].y)];
  for (const point of path.slice(1, 4)) {
    if (point.op !== "line") return undefined;
    points.push(new DOMPoint(point.x, point.y));
  }
  for (let i = 0; i < 4; i++) {
    const a = points[i]!,
      b = points[(i + 1) % 4]!;
    if ((a.x === b.x) === (a.y === b.y)) return undefined;
  }
  return points;
}

/** Opaque same-color diamond fill and stroke have one outer coverage edge. */
export function fillStrokeDiamond(
  context: CanvasRenderingContext2D,
  command: Extract<DrawCommand, { op: "path" }>,
): boolean {
  if (
    !command.fill ||
    command.fill.toLowerCase() !== command.stroke.toLowerCase() ||
    command.lineWidth <= 0 ||
    context.globalAlpha !== 1 ||
    context.globalCompositeOperation !== "source-over" ||
    context.lineJoin !== "miter" ||
    context.getLineDash().length ||
    command.path.length !== 5 ||
    command.path[0]?.op !== "move" ||
    command.path[4]?.op !== "close"
  )
    return false;
  const points = [new DOMPoint(command.path[0].x, command.path[0].y)];
  for (const point of command.path.slice(1, 4)) {
    if (point.op !== "line") return false;
    points.push(new DOMPoint(point.x, point.y));
  }
  const left = Math.min(...points.map((p) => p.x)),
    right = Math.max(...points.map((p) => p.x));
  const top = Math.min(...points.map((p) => p.y)),
    bottom = Math.max(...points.map((p) => p.y));
  const cx = (left + right) / 2,
    cy = (top + bottom) / 2;
  const rx = (right - left) / 2,
    ry = (bottom - top) / 2;
  const diagonal = Math.hypot(rx, ry);
  if (
    !rx ||
    !ry ||
    diagonal / Math.min(rx, ry) > context.miterLimit ||
    !points.every((p, i) => {
      const next = points[(i + 1) % 4]!;
      return (
        p.x !== next.x &&
        p.y !== next.y &&
        ((p.x === cx && (p.y === top || p.y === bottom)) ||
          (p.y === cy && (p.x === left || p.x === right)))
      );
    })
  )
    return false;
  const dx = (command.lineWidth * diagonal) / (2 * ry),
    dy = (command.lineWidth * diagonal) / (2 * rx);
  if (![dx, dy].every(Number.isFinite)) return false;
  const path = new Path2D();
  points.forEach((point, index) => {
    const x = point.x === cx ? cx : point.x + (point.x === left ? -dx : dx);
    const y = point.y === cy ? cy : point.y + (point.y === top ? -dy : dy);
    if (index === 0) path.moveTo(x, y);
    else path.lineTo(x, y);
  });
  path.closePath();
  context.fill(path);
  return true;
}

/** PDF rasterizers hint rectangular clipping edges in device coordinates. */
export function pdfClipPath(
  context: CanvasRenderingContext2D,
  path: PathSegment[],
  mode: "integer" | "fractional" | "pdf",
  commands: readonly DrawCommand[],
  index: number,
): PathSegment[] {
  let following = index + 1,
    next = commands[following];
  const matrix = context.getTransform();
  let shading = matrix;
  if (mode === "pdf") {
    while (next?.op === "style" || next?.op === "transform") {
      if (next.op === "transform") {
        const m = next.matrix;
        shading = shading.multiply(
          new DOMMatrix([m.a, m.b, m.c, m.d, m.e, m.f]),
        );
      }
      next = commands[++following];
    }
  }
  const gradient =
    next?.op === "gradientRect" ||
    next?.op === "radialGradientRect" ||
    (next?.op === "transform" && commands[index + 2]?.op === "gradientRect");
  if (mode === "fractional" || (mode !== "pdf" && !gradient)) return path;
  const points = rectangleCorners(path);
  if (!points || !aligned(matrix)) return path;
  const inverse = matrix.inverse();
  if (
    ![inverse.a, inverse.b, inverse.c, inverse.d, inverse.e, inverse.f].every(
      Number.isFinite,
    )
  )
    return path;
  const device = points.map((point) => matrix.transformPoint(point));
  if (
    !device.every(
      (point) => Number.isFinite(point.x) && Number.isFinite(point.y),
    )
  )
    return path;
  const left = Math.min(...device.map((point) => point.x)),
    right = Math.max(...device.map((point) => point.x));
  const top = Math.min(...device.map((point) => point.y)),
    bottom = Math.max(...device.map((point) => point.y));
  if (
    mode === "pdf" &&
    next?.op === "gradientRect" &&
    aligned(shading) &&
    next.rect.width > 0 &&
    next.stops.length >= 2
  ) {
    const first = next.stops[0]!,
      last = next.stops[next.stops.length - 1]!;
    const start = shading.transformPoint(
      new DOMPoint(next.rect.x + next.rect.width * first.position, next.rect.y),
    );
    const end = shading.transformPoint(
      new DOMPoint(next.rect.x + next.rect.width * last.position, next.rect.y),
    );
    let y0 = Math.floor(top),
      y3 = Math.ceil(bottom),
      y1 = y0 + 1,
      y2 = y3 - 1;
    let correctLeft = true,
      correctRight = true;
    if (start.y === end.y) {
      const min = Math.min(start.x, end.x),
        max = Math.max(start.x, end.x);
      correctLeft = min < Math.floor(left) - 1 && Math.floor(left) - 1 < max;
      correctRight = min < Math.ceil(right) && Math.ceil(right) < max;
    } else {
      y1 = Math.max(y1, Math.floor(Math.min(start.y, end.y)) + 1);
      y2 = Math.min(y2, Math.ceil(Math.max(start.y, end.y)));
    }
    y1 = Math.min(y3, Math.max(y0, y1));
    y2 = Math.max(y1, Math.min(y3, y2));
    // Native shading clips use four horizontal samples and gamma; only interior-domain spans gain full side coverage.
    const countLeft = 4 - Math.floor((left - Math.floor(left)) * 4);
    const countRight =
      right === Math.floor(right)
        ? 4
        : Math.floor((right - Math.floor(right)) * 4) + 1;
    const alpha = (count: number) =>
      Math.round(Math.pow(count / 4, 1.5) * 255) / 255;
    const x0 = Math.floor(left) + 1 - alpha(countLeft),
      x3 = Math.ceil(right) - 1 + alpha(countRight);
    const x1 = correctLeft && countLeft >= 2 ? Math.floor(left) : x0;
    const x2 = correctRight && countRight >= 2 ? Math.ceil(right) : x3;
    // shortcut: smaller clips retain existing coverage; extend after native subpixel controls.
    if (right - left >= 1 && bottom - top >= 1 && x3 > x0) {
      const polygon = [
        [x0, y0],
        [x3, y0],
        [x3, y1],
        [x2, y1],
        [x2, y2],
        [x3, y2],
        [x3, y3],
        [x0, y3],
        [x0, y2],
        [x1, y2],
        [x1, y1],
        [x0, y1],
      ];
      let minX = -Infinity,
        maxX = Infinity,
        minY = -Infinity,
        maxY = Infinity;
      const limit = (edge: DOMPoint, inside: DOMPoint) => {
        if (edge.x < inside.x) minX = Math.ceil(edge.x);
        else if (edge.x > inside.x) maxX = Math.floor(edge.x) + 1;
        if (edge.y < inside.y) minY = Math.ceil(edge.y);
        else if (edge.y > inside.y) maxY = Math.floor(edge.y) + 1;
      };
      // Unextended shading ends test integer pixel positions before color sampling.
      if (first.position === 0) limit(start, end);
      if (last.position === 1) limit(end, start);
      return [
        ...polygon.map(([x, y], i): PathSegment => {
          const p = inverse.transformPoint(
            new DOMPoint(
              Math.max(minX, Math.min(maxX, x!)),
              Math.max(minY, Math.min(maxY, y!)),
            ),
          );
          return { op: i === 0 ? "move" : "line", x: p.x, y: p.y };
        }),
        { op: "close" },
      ];
    }
  }
  const pdf = mode === "pdf" && !gradient;
  const [x0, x1] = pdf ? [left, right] : pixelEdges(left, right);
  const [y0, y1] = pdf
    ? [Math.floor(top), Math.ceil(bottom)]
    : pixelEdges(top, bottom);
  return [
    ...device.map((point, index): PathSegment => {
      const local = inverse.transformPoint(
        new DOMPoint(point.x === left ? x0 : x1, point.y === top ? y0 : y1),
      );
      return { op: index === 0 ? "move" : "line", x: local.x, y: local.y };
    }),
    { op: "close" },
  ];
}

export type ClipBounds = [
  left: number,
  top: number,
  right: number,
  bottom: number,
];

export function fractionalClipBounds(
  context: CanvasRenderingContext2D,
  path: PathSegment[],
): ClipBounds | undefined {
  const matrix = context.getTransform();
  const points = rectangleCorners(path);
  if (!points || !aligned(matrix)) return undefined;
  const device = points.map((point) => matrix.transformPoint(point));
  const x = device.map((point) => point.x);
  const y = device.map((point) => point.y);
  const left = Math.min(...x),
    right = Math.max(...x);
  const top = Math.min(...y),
    bottom = Math.max(...y);
  if (
    ![left, top, right, bottom].every(Number.isFinite) ||
    left >= right ||
    top >= bottom ||
    [left, top, right, bottom].every(Number.isInteger)
  )
    return undefined;
  return [left, top, right, bottom];
}

export function clipDeviceRectangle(
  context: CanvasRenderingContext2D,
  [left, top, right, bottom]: ClipBounds,
  glyphs: boolean,
): void {
  const path = new Path2D();
  if (right > left && bottom > top) {
    // PDF glyph masks use whole-pixel clip bounds, unlike vector fills.
    const x = glyphs ? Math.floor(left) : left;
    const y = glyphs ? Math.floor(top) : top;
    path.rect(
      x,
      y,
      (glyphs ? Math.ceil(right) : right) - x,
      (glyphs ? Math.ceil(bottom) : bottom) - y,
    );
  }
  const transform = context.getTransform();
  context.resetTransform();
  context.clip(path);
  context.setTransform(transform);
}

/** Opaque rectangular fills share the native stroke-adjust boundary grid. */
export function pixelRectangleFill(
  context: CanvasRenderingContext2D,
  rect: Extract<DrawCommand, { op: "fillRect" }>["rect"],
): boolean {
  if (
    context.globalAlpha !== 1 ||
    context.globalCompositeOperation !== "source-over" ||
    rect.width <= 0 ||
    rect.height <= 0
  )
    return false;
  const matrix = context.getTransform();
  if (!aligned(matrix)) return false;
  const a = matrix.transformPoint(new DOMPoint(rect.x, rect.y));
  const b = matrix.transformPoint(
    new DOMPoint(rect.x + rect.width, rect.y + rect.height),
  );
  const left = Math.round(Math.min(a.x, b.x)),
    right = Math.round(Math.max(a.x, b.x));
  const top = Math.round(Math.min(a.y, b.y)),
    bottom = Math.round(Math.max(a.y, b.y));
  // shortcut: collapsed fills keep Canvas coverage; extend for a failing native comparison.
  if (
    ![left, right, top, bottom].every(Number.isFinite) ||
    right <= left ||
    bottom <= top
  )
    return false;
  context.save();
  try {
    context.resetTransform();
    context.fillRect(left, top, right - left, bottom - top);
  } finally {
    context.restore();
  }
  return true;
}

function rectangleDashClip(
  context: CanvasRenderingContext2D,
  local: DOMPoint[],
  device: DOMPoint[],
  wx: number,
  wy: number,
  pdf: boolean,
  open: boolean,
): Path2D | undefined {
  const dash = context.getLineDash();
  if (
    context.lineCap !== "butt" ||
    context.lineJoin !== "miter" ||
    context.lineDashOffset !== 0 ||
    dash.some((value) => !Number.isFinite(value) || value <= 0)
  )
    return undefined;
  const path = new Path2D();
  const corner = (point: DOMPoint) => {
    const [x0, x1] = pixelEdges(point.x - wx, point.x + wx, pdf);
    const [y0, y1] = pixelEdges(point.y - wy, point.y + wy, pdf);
    path.rect(x0, y0, x1 - x0, y1 - y0);
  };
  let index = 0,
    remaining = dash[0]!,
    steps = 0,
    endsOn = false;
  for (let edge = 0; edge < 4; edge++) {
    const a = local[edge]!,
      b = local[(edge + 1) % 4]!;
    const p = device[edge]!,
      q = device[(edge + 1) % 4]!;
    if ((p.x === q.x) === (p.y === q.y)) return undefined;
    const length = Math.hypot(b.x - a.x, b.y - a.y);
    let at = 0;
    while (at < length) {
      // shortcut: finer patterns use Canvas; extend the budget only with measured native cases.
      if (++steps > 8192) return undefined;
      const step = Math.min(remaining, length - at);
      if (at + step <= at) return undefined;
      const atEnd = step === length - at;
      const end = atEnd ? length : at + step;
      endsOn = index % 2 === 0;
      if (endsOn) {
        if (p.x === q.x) {
          const [x0, x1] = pixelEdges(p.x - wx, p.x + wx, pdf);
          const y0 = Math.round(p.y + ((q.y - p.y) * at) / length);
          const y1 = Math.round(p.y + ((q.y - p.y) * end) / length);
          path.rect(x0, Math.min(y0, y1), x1 - x0, Math.abs(y1 - y0));
        } else {
          const [y0, y1] = pixelEdges(p.y - wy, p.y + wy, pdf);
          const x0 = Math.round(p.x + ((q.x - p.x) * at) / length);
          const x1 = Math.round(p.x + ((q.x - p.x) * end) / length);
          path.rect(Math.min(x0, x1), y0, Math.abs(x1 - x0), y1 - y0);
        }
        if (edge < 3 && atEnd && remaining > step) corner(q);
      }
      at = end;
      remaining -= step;
      if (remaining === 0) {
        index = (index + 1) % dash.length;
        remaining = dash[index]!;
      }
    }
  }
  if (endsOn && !open) corner(device[0]!);
  return path;
}

/** Native rectangles align each side of their stroke outline. */
export function pixelRectangleStroke(
  context: CanvasRenderingContext2D,
  command: Extract<DrawCommand, { op: "path" | "strokeRect" }>,
  pdf = false,
): boolean {
  const segments: PathSegment[] =
    command.op === "strokeRect"
      ? [
          { op: "move", x: command.rect.x, y: command.rect.y },
          {
            op: "line",
            x: command.rect.x + command.rect.width,
            y: command.rect.y,
          },
          {
            op: "line",
            x: command.rect.x + command.rect.width,
            y: command.rect.y + command.rect.height,
          },
          {
            op: "line",
            x: command.rect.x,
            y: command.rect.y + command.rect.height,
          },
          { op: "close" },
        ]
      : command.path;
  const open = segments.length === 5 && segments[4]?.op === "line";
  if (open && (context.lineCap !== "butt" || context.lineJoin !== "miter"))
    return false;
  // Native open rectangle strokes round both edges, including collapsed subpixel pens.
  pdf ||= open;
  const round = pdf && context.lineJoin === "round";
  const dashed = context.getLineDash().length > 0;
  if (
    command.lineWidth <= 0 ||
    (!round &&
      (context.lineJoin !== "miter" || context.miterLimit < Math.SQRT2)) ||
    (dashed && segments.length !== 5) ||
    !segments.length ||
    segments.length % 5 ||
    (segments.length > 5 &&
      segments.some((segment, i) => i % 5 === 4 && segment.op !== "close")) ||
    (!pdf && segments.length !== 5)
  )
    return false;
  const m = context.getTransform();
  const scale = Math.max(
    Math.abs(m.a),
    Math.abs(m.b),
    Math.abs(m.c),
    Math.abs(m.d),
  );
  const epsilon = scale * Number.EPSILON * 16;
  const diagonal = Math.abs(m.b) <= epsilon && Math.abs(m.c) <= epsilon;
  const quarter = Math.abs(m.a) <= epsilon && Math.abs(m.d) <= epsilon;
  const determinant = m.a * m.d - m.b * m.c;
  if ((!diagonal && !quarter) || !determinant || !Number.isFinite(determinant))
    return false;
  const wx =
    (command.lineWidth * (diagonal ? Math.abs(m.a) : Math.abs(m.c))) / 2;
  const wy =
    (command.lineWidth * (diagonal ? Math.abs(m.d) : Math.abs(m.b))) / 2;
  // shortcut: translucent open dashes with fractional device pens use Canvas until native endpoint coverage is qualified.
  if (
    open &&
    dashed &&
    context.globalAlpha !== 1 &&
    (!Number.isInteger(wx * 2) || !Number.isInteger(wy * 2))
  )
    return false;
  const path = new Path2D();
  let dashClip: Path2D | undefined;
  for (let index = 0; index < segments.length; index += 5) {
    const corners = rectangleCorners(segments.slice(index, index + 5));
    if (!corners) return false;
    const points = corners.map((point) => m.transformPoint(point));
    if (!points.every((p) => Number.isFinite(p.x) && Number.isFinite(p.y)))
      return false;
    if (dashed) {
      dashClip = rectangleDashClip(context, corners, points, wx, wy, pdf, open);
      if (!dashClip) return false;
    }
    const xs = points.map((point) => point.x),
      ys = points.map((point) => point.y);
    const [left, innerLeft] = pixelEdges(
      Math.min(...xs) - wx,
      Math.min(...xs) + wx,
      pdf,
    );
    const [innerRight, right] = pixelEdges(
      Math.max(...xs) - wx,
      Math.max(...xs) + wx,
      pdf,
    );
    const [top, innerTop] = pixelEdges(
      Math.min(...ys) - wy,
      Math.min(...ys) + wy,
      pdf,
    );
    const [innerBottom, bottom] = pixelEdges(
      Math.max(...ys) - wy,
      Math.max(...ys) + wy,
      pdf,
    );
    if (round)
      path.roundRect(left, top, right - left, bottom - top, { x: wx, y: wy });
    else if (open) {
      // Butt caps meet at rounded path endpoints without a join at the first corner.
      // shortcut: omit 0.01-pixel endpoint fringes; extend when a native comparison exceeds tolerance.
      const start = points[0]!;
      const x = Math.max(left, Math.min(right, Math.round(start.x)));
      const y = Math.max(top, Math.min(bottom, Math.round(start.y)));
      const cx = (Math.min(...xs) + Math.max(...xs)) / 2;
      const cy = (Math.min(...ys) + Math.max(...ys)) / 2;
      const area = points.reduce((sum, p, i) => {
        const next = points[(i + 1) % 4]!;
        return sum + p.x * next.y - p.y * next.x;
      }, 0);
      const corners =
        area < 0 ? [start, points[3]!, points[2]!, points[1]!] : points;
      corners.forEach((point, i) => {
        const px = point.x < cx ? left : right;
        const py = point.y < cy ? top : bottom;
        if (i === 0) {
          const nextX = corners[1]!.x < cx ? left : right;
          const vertical = px === nextX;
          path.moveTo(vertical ? x : px, vertical ? py : y);
          path.lineTo(x, y);
          path.lineTo(vertical ? px : x, vertical ? y : py);
        } else path.lineTo(px, py);
      });
      path.closePath();
    } else path.rect(left, top, right - left, bottom - top);
    if (innerRight > innerLeft && innerBottom > innerTop)
      path.rect(
        innerRight,
        innerTop,
        innerLeft - innerRight,
        innerBottom - innerTop,
      );
  }
  context.save();
  try {
    context.resetTransform();
    if (dashClip) context.clip(dashClip);
    context.fillStyle = context.strokeStyle;
    context.fill(path);
  } finally {
    context.restore();
  }
  return true;
}
