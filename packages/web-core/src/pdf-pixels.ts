import type {
  ClipBounds,
  DrawCommand,
  GradientClip,
  PathSegment,
  RectangleDashSpan,
} from "@open-document/wasm/abi/drawing";
export type { ClipBounds } from "@open-document/wasm/abi/drawing";

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

type RectanglePoint = Pick<DOMPoint, "x" | "y">;
type RectangleCorners = [
  RectanglePoint,
  RectanglePoint,
  RectanglePoint,
  RectanglePoint,
];

function rectangleCorners(
  path: PathSegment[],
  offset: number,
  generated: boolean,
): RectangleCorners | undefined {
  const a = path[offset],
    b = path[offset + 1],
    c = path[offset + 2],
    d = path[offset + 3];
  if (
    a?.op !== "move" ||
    b?.op !== "line" ||
    c?.op !== "line" ||
    d?.op !== "line"
  )
    return undefined;
  const corners: RectangleCorners = [a, b, c, d];
  if (generated) {
    const end = path[offset + 4];
    if (
      end?.op !== "close" &&
      !(end?.op === "line" && end.x === a.x && end.y === a.y)
    )
      return undefined;
    for (let i = 0; i < 4; i++) {
      const first = corners[i]!,
        next = corners[(i + 1) % 4]!;
      if ((first.x === next.x) === (first.y === next.y)) return undefined;
    }
  }
  return corners;
}

function rectanglePath([left, top, right, bottom]: ClipBounds): Path2D {
  const path = new Path2D();
  path.moveTo(left, top);
  path.lineTo(right, top);
  path.lineTo(right, bottom);
  path.lineTo(left, bottom);
  path.closePath();
  return path;
}

function transformClipBounds(
  matrix: DOMMatrix,
  [left, top, right, bottom]: ClipBounds,
): ClipBounds {
  const first = matrix.transformPoint({ x: left, y: top });
  const last = matrix.transformPoint({ x: right, y: bottom });
  return [
    Math.min(first.x, last.x),
    Math.min(first.y, last.y),
    Math.max(first.x, last.x),
    Math.max(first.y, last.y),
  ];
}

/** Hint the core's rectangular clip in device coordinates. */
export function pixelClipRectangle(
  context: CanvasRenderingContext2D,
  rectangle: ClipBounds,
  deviceClips: boolean,
  domain?: GradientClip,
): { path: Path2D; bounds?: ClipBounds } {
  const original = () => ({ path: rectanglePath(rectangle) });
  if (
    rectangle[0] === rectangle[2] ||
    rectangle[1] === rectangle[3] ||
    (!deviceClips && !domain)
  )
    return original();
  const matrix = context.getTransform();
  if (!aligned(matrix)) return original();
  const inverse = matrix.inverse();
  if (
    ![inverse.a, inverse.b, inverse.c, inverse.d, inverse.e, inverse.f].every(
      Number.isFinite,
    )
  )
    return original();
  const device = transformClipBounds(matrix, rectangle);
  if (!device.every(Number.isFinite)) return original();
  const [left, top, right, bottom] = device;
  const axial = deviceClips ? domain?.axial : undefined;
  let shading = matrix;
  if (axial)
    for (const m of axial.transforms)
      shading = shading.multiply(new DOMMatrix([m.a, m.b, m.c, m.d, m.e, m.f]));
  if (axial && aligned(shading)) {
    const start = shading.transformPoint(new DOMPoint(axial.startX, axial.y));
    const end = shading.transformPoint(new DOMPoint(axial.endX, axial.y));
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
      if (axial.startBounded) limit(start, end);
      if (axial.endBounded) limit(end, start);
      const path = new Path2D();
      for (const [i, [x, y]] of polygon.entries()) {
        const p = inverse.transformPoint({
          x: Math.max(minX, Math.min(maxX, x!)),
          y: Math.max(minY, Math.min(maxY, y!)),
        });
        if (i === 0) path.moveTo(p.x, p.y);
        else path.lineTo(p.x, p.y);
      }
      path.closePath();
      return { path };
    }
  }
  const fractional = deviceClips && !domain;
  const [x0, x1] = fractional ? [left, right] : pixelEdges(left, right);
  const [y0, y1] = fractional
    ? [Math.floor(top), Math.ceil(bottom)]
    : pixelEdges(top, bottom);
  const local = transformClipBounds(inverse, [
    x0,
    y0,
    left === right ? x0 : x1,
    top === bottom ? y0 : y1,
  ]);
  const path = rectanglePath(local);
  if (!deviceClips) return { path };
  // Preserve the device round trip before choosing deferred fractional coverage.
  const bounds = transformClipBounds(matrix, local);
  return bounds.every(Number.isFinite) &&
    bounds[0] < bounds[2] &&
    bounds[1] < bounds[3] &&
    !bounds.every(Number.isInteger)
    ? { path, bounds }
    : { path };
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
  local: RectangleCorners,
  device: DOMPoint[],
  wx: number,
  wy: number,
  pdf: boolean,
  open: boolean,
  prepared: RectangleDashSpan[] | undefined,
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
  for (let edge = 0; edge < 4; edge++) {
    const p = device[edge]!,
      q = device[(edge + 1) % 4]!;
    if ((p.x === q.x) === (p.y === q.y)) return undefined;
  }
  const span = (
    edge: number,
    length: number,
    at: number,
    end: number,
    join: boolean,
  ) => {
    const p = device[edge]!,
      q = device[(edge + 1) % 4]!;
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
    if (join) corner(q);
  };
  if (prepared) {
    for (const piece of prepared) span(...piece);
    return path;
  }
  let index = 0,
    remaining = dash[0]!,
    steps = 0,
    endsOn = false;
  for (let edge = 0; edge < 4; edge++) {
    const a = local[edge]!,
      b = local[(edge + 1) % 4]!;
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
      if (endsOn)
        span(edge, length, at, end, edge < 3 && atEnd && remaining > step);
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
  generated = false,
  prepared?: RectangleDashSpan[],
): boolean {
  if (
    !generated &&
    command.op === "path" &&
    command.strokeGeometry !== "rectangles" &&
    command.strokeGeometry !== "openRectangle"
  )
    return false;
  const length = command.op === "path" ? command.path.length : 5;
  const open =
    command.op === "path" &&
    (generated
      ? length === 5 && command.path[4]?.op === "line"
      : command.strokeGeometry === "openRectangle");
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
    ((open || dashed || !pdf) && length !== 5) ||
    !length ||
    length % 5 ||
    (generated &&
      length > 5 &&
      command.op === "path" &&
      command.path.some((segment, i) => i % 5 === 4 && segment.op !== "close"))
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
  for (let index = 0; index < length; index += 5) {
    let corners: RectangleCorners;
    if (command.op === "strokeRect") {
      const { x, y, width, height } = command.rect;
      const right = x + width,
        bottom = y + height;
      if (x === right || y === bottom) return false;
      corners = [
        { x, y },
        { x: right, y },
        { x: right, y: bottom },
        { x, y: bottom },
      ];
    } else {
      // Only device-flattened curves need geometric classification here.
      const found = rectangleCorners(command.path, index, generated);
      if (!found) return false;
      corners = found;
    }
    const [start, , opposite] = corners;
    let points: DOMPoint[] = [];
    let bounds: ClipBounds;
    if (
      !dashed &&
      !open &&
      aligned(m) &&
      start.x !== opposite.x &&
      start.y !== opposite.y
    ) {
      bounds = transformClipBounds(m, [
        start.x,
        start.y,
        opposite.x,
        opposite.y,
      ]);
    } else {
      points = corners.map((point) => m.transformPoint(point));
      bounds = [Infinity, Infinity, -Infinity, -Infinity];
      for (const { x, y } of points) {
        bounds[0] = Math.min(bounds[0], x);
        bounds[1] = Math.min(bounds[1], y);
        bounds[2] = Math.max(bounds[2], x);
        bounds[3] = Math.max(bounds[3], y);
      }
    }
    if (!bounds.every(Number.isFinite)) return false;
    const [minX, minY, maxX, maxY] = bounds;
    if (dashed) {
      dashClip = rectangleDashClip(
        context,
        corners,
        points,
        wx,
        wy,
        pdf,
        open,
        prepared,
      );
      if (!dashClip) return false;
    }
    const [left, innerLeft] = pixelEdges(minX - wx, minX + wx, pdf);
    const [innerRight, right] = pixelEdges(maxX - wx, maxX + wx, pdf);
    const [top, innerTop] = pixelEdges(minY - wy, minY + wy, pdf);
    const [innerBottom, bottom] = pixelEdges(maxY - wy, maxY + wy, pdf);
    if (round)
      path.roundRect(left, top, right - left, bottom - top, { x: wx, y: wy });
    else if (open) {
      // Butt caps meet at rounded path endpoints without a join at the first corner.
      // shortcut: omit 0.01-pixel endpoint fringes; extend when a native comparison exceeds tolerance.
      const start = points[0]!;
      const x = Math.max(left, Math.min(right, Math.round(start.x)));
      const y = Math.max(top, Math.min(bottom, Math.round(start.y)));
      const cx = (minX + maxX) / 2;
      const cy = (minY + maxY) / 2;
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
