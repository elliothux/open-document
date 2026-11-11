import type {
  DrawGlyphRun,
  DrawMatrix,
  PdfGlyphCommand,
} from "@open-document/wasm/abi/drawing";
import type { CanvasRasterMode } from "./drawing.js";
import { strokeCoverage } from "./pdf-stroke.js";

type Point = { x: number; y: number };
type GlyphSegment = { op: string; values: number[] };

export interface GlyphPath {
  path: Path2D;
  bounds: Point[] | null;
  segments?: GlyphSegment[] | undefined;
}

export function compileGlyphPath(source: string): GlyphPath {
  const path = new Path2D(source);
  // shortcut: other SVG grammars retain Canvas strokes; extend after independent native evidence.
  if (source.length > 65536) return { path, bounds: null };
  const tokens: readonly string[] =
    source.match(/[MLHVQCZ]|[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?/g) ?? [];
  if (
    tokens.length > 16384 ||
    tokens[0] !== "M" ||
    tokens.join("") !== source.replace(/[\s,]/g, "")
  )
    return { path, bounds: null };
  const arity: Readonly<Record<string, number>> = {
    M: 2,
    L: 2,
    H: 1,
    V: 1,
    Q: 4,
    C: 6,
  };
  const segments: GlyphSegment[] | undefined =
    tokens.includes("Q") || tokens.includes("C") ? [] : undefined;
  let index = 0,
    op = "",
    x = 0,
    y = 0,
    firstX = 0,
    firstY = 0,
    minX = Infinity,
    minY = Infinity,
    maxX = -Infinity,
    maxY = -Infinity;
  const point = (px: number, py: number) => {
    minX = Math.min(minX, px);
    minY = Math.min(minY, py);
    maxX = Math.max(maxX, px);
    maxY = Math.max(maxY, py);
  };
  while (index < tokens.length) {
    const token = tokens[index]!;
    if (/^[MLHVQCZ]$/.test(token)) {
      op = token;
      index++;
      if (op === "Z") {
        segments?.push({ op, values: [] });
        x = firstX;
        y = firstY;
        op = "";
        continue;
      }
    }
    const count = arity[op];
    if (!count || index + count > tokens.length) return { path, bounds: null };
    const values = tokens.slice(index, index + count).map(Number);
    if (!values.every(Number.isFinite)) return { path, bounds: null };
    if (op === "H") {
      x = values[0]!;
      point(x, y);
      segments?.push({ op: "L", values: [x, y] });
    } else if (op === "V") {
      y = values[0]!;
      point(x, y);
      segments?.push({ op: "L", values: [x, y] });
    } else {
      segments?.push({ op, values });
      for (let i = 0; i < values.length; i += 2)
        point(values[i]!, values[i + 1]!);
      x = values.at(-2)!;
      y = values.at(-1)!;
      if (op === "M") {
        firstX = x;
        firstY = y;
        op = "L";
      }
    }
    index += count;
  }
  return {
    path,
    segments,
    bounds: [minX, minY, maxX, maxY].every(Number.isFinite)
      ? [
          { x: minX, y: minY },
          { x: maxX, y: maxY },
        ]
      : null,
  };
}

function midpoint(a: Point, b: Point): Point {
  return { x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 };
}

function flattenGlyphStroke(
  outline: GlyphPath,
  scale: number,
  samples: number,
): Path2D {
  if (!outline.segments) return outline.path;
  const result = new Path2D();
  let remaining = Math.min(16384, samples);
  let point: Point = { x: 0, y: 0 },
    first = point;
  const curve = (
    a: Point,
    b: Point,
    c: Point,
    d: Point,
    depth: number,
  ): boolean => {
    if (--remaining < 0) return false;
    const m = midpoint(a, d);
    // Splash compares both cubic control points with the chord midpoint.
    if (
      depth === 10 ||
      (Math.hypot(b.x - m.x, b.y - m.y) * scale <= 1 &&
        Math.hypot(c.x - m.x, c.y - m.y) * scale <= 1)
    ) {
      result.lineTo(d.x, d.y);
      return true;
    }
    const ab = midpoint(a, b),
      bc = midpoint(b, c),
      cd = midpoint(c, d);
    const abc = midpoint(ab, bc),
      bcd = midpoint(bc, cd);
    const center = midpoint(abc, bcd);
    return (
      curve(a, ab, abc, center, depth + 1) &&
      curve(center, bcd, cd, d, depth + 1)
    );
  };
  for (const { op, values } of outline.segments) {
    // shortcut: contours exceeding subdivision work retain their original curves.
    if (--remaining < 0) return outline.path;
    if (op === "Z") {
      result.closePath();
      point = first;
      continue;
    }
    const end = { x: values.at(-2)!, y: values.at(-1)! };
    if (op === "M") {
      result.moveTo(end.x, end.y);
      first = end;
    } else if (op === "L") result.lineTo(end.x, end.y);
    else {
      const control = { x: values[0]!, y: values[1]! };
      const cubic = (from: Point): Point => ({
        x: (from.x + 2 * control.x) / 3,
        y: (from.y + 2 * control.y) / 3,
      });
      const b = op === "Q" ? cubic(point) : control;
      const c = op === "Q" ? cubic(end) : { x: values[2]!, y: values[3]! };
      if (!curve(point, b, c, end, 0)) return outline.path;
    }
    point = end;
  }
  return result;
}

export function drawGlyphs(
  context: CanvasRenderingContext2D,
  commands: DrawGlyphRun[] | PdfGlyphCommand,
  mode: CanvasRasterMode,
  pixelSize: boolean,
  sourceMatrix: DrawMatrix | undefined,
  paths: ReadonlyMap<string, GlyphPath>,
  availablePixels: number,
  remainingWork: number,
): number {
  let work = 0;
  const matrix = pixelSize ? context.getTransform() : undefined;
  const nativeScale = Math.fround(96 / 72);
  const nativeScreen =
    matrix?.b === 0 &&
    matrix.c === 0 &&
    Math.abs(matrix.a) === nativeScale &&
    Math.abs(matrix.d) === nativeScale;
  const pdf = Array.isArray(commands) ? undefined : commands;
  const runs = Array.isArray(commands) ? commands : [commands.run];
  for (const [upem, bounds, strokeWidth, scaleX, scaleY, glyphs] of runs) {
    for (const [resource, tx, ty] of glyphs) {
      const key =
        typeof resource === "string" ? resource : pdf?.outlines[resource];
      if (key === undefined) throw new Error("Invalid PDF outline index");
      const outline = paths.get(key);
      if (!outline) throw new Error(`Missing outline: ${key}`);
      const screenOutline =
        nativeScreen && strokeWidth === 0
          ? paths.get(
              `${key}:screen:${Math.round(Math.abs(scaleY) * upem * (2540 / 72))}`,
            )
          : undefined;
      const path = screenOutline?.path ?? outline.path;
      context.save();
      try {
        const x = pdf ? pdf.origin[0] : tx;
        const y = pdf ? pdf.origin[1] : ty;
        let source = sourceMatrix;
        if (pdf) {
          const [a, b, c, d] = pdf.matrix;
          context.transform(a, b, c, d, tx, ty);
          if (source) {
            source = {
              a: source.a * a + source.c * b,
              b: source.b * a + source.d * b,
              c: source.a * c + source.c * d,
              d: source.b * c + source.d * d,
              e: source.a * tx + source.c * ty + source.e,
              f: source.b * tx + source.d * ty + source.f,
            };
          }
        }
        context.translate(x, y);
        context.scale(scaleX, scaleY);
        // Canvas stores its current transform at float precision; retain source origins for the PDF grid.
        let m =
          mode === "pdf" && !pixelSize && source
            ? {
                a: source.a * scaleX,
                b: source.b * scaleX,
                c: source.c * scaleY,
                d: source.d * scaleY,
                e: source.a * x + source.c * y + source.e,
                f: source.b * x + source.d * y + source.f,
              }
            : context.getTransform();
        if (pixelSize && m.b === 0 && m.c === 0) {
          const size = Math.abs(m.d) * upem;
          const height = Math.round(size);
          if (height === 0) continue;
          // Snap the em height to pixel rows while preserving the logical width.
          const scale = screenOutline ? 1 : height / upem;
          context.setTransform(
            screenOutline ? Math.sign(m.a) : m.a,
            0,
            0,
            Math.sign(m.d) * scale,
            m.e,
            m.f,
          );
          m = context.getTransform();
        }
        // Quarter-turn text shares the PDF row grid.
        const quarterTurn = m.a === 0 && m.d === 0;
        const rasterMode = quarterTurn && mode === "fractional" ? "pdf" : mode;
        if (
          (strokeWidth === 0 || pixelSize) &&
          ((m.b === 0 && m.c === 0) ||
            (rasterMode === "pdf" && m.a === 0 && m.d === 0))
        ) {
          // Native glyph caches drop horizontal phases when the padded font bounds exceed 50px.
          const axis = quarterTurn ? 0 : 1;
          const scale = quarterTurn ? m.b : m.d;
          const cacheHeight = bounds
            ? Math.abs(
                Math.trunc(scale * bounds[axis + 2]!) -
                  Math.trunc(scale * bounds[axis]),
              ) + 3
            : 0;
          const phases = !pixelSize && cacheHeight > 50 ? 1 : 4;
          const phasedTurn =
            rasterMode === "pdf" &&
            quarterTurn &&
            bounds !== null &&
            !pixelSize;
          context.setTransform(
            m.a,
            m.b,
            m.c,
            m.d,
            rasterMode === "fractional" ||
              phasedTurn ||
              (rasterMode === "pdf" && m.b === 0 && m.c === 0 && !pixelSize)
              ? Math.floor(m.e * phases + (pixelSize ? 0.5 : 0)) / phases
              : rasterMode === "pdf"
                ? m.e
                : Math.trunc(m.e),
            screenOutline
              ? Math.floor(m.f * 4 + 0.5) / 4
              : pixelSize
                ? Math.floor(m.f + 0.5)
                : rasterMode === "integer"
                  ? Math.trunc(m.f)
                  : Math.floor(m.f),
          );
        }
        context.fill(path);
        if (strokeWidth > 0) {
          context.strokeStyle = context.fillStyle;
          context.lineWidth = strokeWidth;
          context.lineJoin = "miter";
          context.miterLimit = 10;
          context.setLineDash([]);
          const budget = {
            samples: Math.min(4194304, remainingWork - work),
            pixels: availablePixels,
            inclusive: false,
          };
          const before = budget.samples;
          if (
            pixelSize ||
            !outline.bounds ||
            context.globalAlpha !== 1 ||
            context.globalCompositeOperation !== "source-over" ||
            m.a === 0 ||
            m.b !== 0 ||
            m.c !== 0 ||
            Math.abs(m.a) !== Math.abs(m.d) ||
            !strokeCoverage(
              context,
              path,
              [outline.bounds],
              (strokeWidth * context.miterLimit) / 2,
              context.getTransform(),
              budget,
              (samples) => flattenGlyphStroke(outline, Math.abs(m.a), samples),
            )
          )
            context.stroke(path);
          else work += before - budget.samples;
        }
      } finally {
        context.restore();
      }
    }
  }
  return work;
}
