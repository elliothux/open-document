import type {
  DrawCommand,
  DrawRect,
  DrawingBatch,
  DrawingRegion,
} from "@open-document/wasm/abi/drawing";
import { compileGlyphPath, type GlyphPath } from "./drawing-glyphs.js";

type Glyphs = Extract<DrawCommand, { op: "glyphs" }>;

function equal(before: DrawCommand, after: DrawCommand): boolean {
  return before === after || JSON.stringify(before) === JSON.stringify(after);
}

/** Finds device pixels affected by edits that only change unstroked Office text. */
export function textDamage(
  before: DrawingRegion,
  after: DrawingRegion,
  scale: number,
  previousOutlines: DrawingBatch["outlines"],
  outlines: DrawingBatch["outlines"],
  paths: ReadonlyMap<string, GlyphPath>,
  imageUnchanged: (key: string) => boolean,
): DrawRect | undefined {
  if (
    before.width !== after.width ||
    before.height !== after.height ||
    before.glyphRaster !== after.glyphRaster ||
    before.backingClip !== after.backingClip ||
    before.deviceClips ||
    after.deviceClips ||
    before.imageSampling ||
    after.imageSampling ||
    before.strokeRaster !== after.strokeRaster ||
    after.strokeRaster === "coverage" ||
    before.glyphRaster === "coverage" ||
    before.commands.length + after.commands.length > 4096
  )
    return undefined;

  const sources = new Map(previousOutlines.map(({ key, path }) => [key, path]));
  for (const { key, path } of outlines) {
    if (sources.has(key) && sources.get(key) !== path) return undefined;
    sources.set(key, path);
  }
  const compiled = new Map<string, GlyphPath>();
  const outline = (key: string): GlyphPath | undefined => {
    const cached = paths.get(key) ?? compiled.get(key);
    if (cached) return cached;
    const source = sources.get(key);
    if (source === undefined) return undefined;
    const path = compileGlyphPath(source);
    compiled.set(key, path);
    return path;
  };

  let left = Infinity,
    top = Infinity,
    right = -Infinity,
    bottom = -Infinity;
  let matrix = new DOMMatrix([scale, 0, 0, scale, 0, 0]);
  const stack: DOMMatrix[] = [];
  let glyphWork = 0;
  const include = (command: Glyphs) => {
    for (const [, , stroke, sx, sy, glyphs] of command.runs) {
      if (stroke !== 0 || (glyphWork += glyphs.length) > 8192) return false;
      for (const [key, x, y] of glyphs) {
        const path = outline(key);
        if (path?.empty) continue;
        const bounds = path?.bounds;
        if (!bounds) return false;
        for (const { x: dx } of bounds) {
          for (const other of bounds) {
            const point = matrix.transformPoint({
              x: command.x + x + dx * sx,
              y: command.y + y + other.y * sy,
            });
            if (!Number.isFinite(point.x) || !Number.isFinite(point.y))
              return false;
            left = Math.min(left, point.x);
            top = Math.min(top, point.y);
            right = Math.max(right, point.x);
            bottom = Math.max(bottom, point.y);
          }
        }
      }
    }
    return true;
  };

  const a = before.commands,
    b = after.commands;
  let i = 0,
    j = 0;
  while (i < a.length || j < b.length) {
    const old = a[i],
      next = b[j];
    if (old?.op === "glyphs" || next?.op === "glyphs") {
      if (old?.op === "glyphs" && next?.op === "glyphs" && equal(old, next)) {
        i++;
        j++;
      } else {
        if (old?.op === "glyphs") {
          if (!include(old)) return undefined;
          i++;
        }
        if (next?.op === "glyphs") {
          if (!include(next)) return undefined;
          j++;
        }
      }
      continue;
    }
    if (!old || !next || !equal(old, next)) return undefined;
    switch (next.op) {
      case "transform": {
        const { a, b, c, d, e, f } = next.matrix;
        stack.push(matrix);
        matrix = matrix.multiply(new DOMMatrix([a, b, c, d, e, f]));
        break;
      }
      case "clipRect":
      case "clipPath":
        stack.push(matrix);
        break;
      case "restore":
        matrix = stack.pop()!;
        break;
      case "image":
        if (!imageUnchanged(next.image.key)) return undefined;
        break;
      case "fillRect":
      case "strokeRect":
      case "strokeBands":
      case "path":
      case "style":
      case "gradientRect":
      case "radialGradientRect":
        break;
      default:
        return undefined;
    }
    i++;
    j++;
  }
  if (left === Infinity) return { x: 0, y: 0, width: 0, height: 0 };
  // Leave space for device-grid snapping and antialiasing.
  const x = Math.floor(left) - 2,
    y = Math.floor(top) - 2;
  return {
    x,
    y,
    width: Math.ceil(right) + 2 - x,
    height: Math.ceil(bottom) + 2 - y,
  };
}
