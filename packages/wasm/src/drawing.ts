import { record } from "./validation.js";

export interface DrawRect {
  x: number;
  y: number;
  width: number;
  height: number;
}

export interface DrawGlyph {
  outline: string;
  x: number;
  y: number;
  scaleX: number;
  scaleY: number;
}

export type DrawCommand =
  | { op: "fillRect"; rect: DrawRect & { color: string } }
  | { op: "strokeRect"; rect: DrawRect; color: string; lineWidth: number }
  | { op: "glyphs"; x: number; y: number; color: string; glyphs: DrawGlyph[] }
  | { op: "image"; image: DrawRect & { key: string } }
  | { op: "clipRect"; rect: DrawRect }
  | { op: "restoreClip" };

/** Platform-independent drawing, with resources shared across regions. */
export interface DrawingBatch {
  pages: DrawingRegion[];
  outlines: { key: string; path: string }[];
  images: string[];
}

export interface DrawingRegion {
  width: number;
  height: number;
  commands: DrawCommand[];
}

function finite(value: unknown): number {
  if (typeof value !== "number" || !Number.isFinite(value))
    throw new Error("Invalid drawing number");
  return value;
}

function rect(value: unknown): void {
  const object = record(value);
  finite(object.x);
  finite(object.y);
  if (finite(object.width) < 0 || finite(object.height) < 0)
    throw new Error("Invalid drawing rectangle");
}

function color(value: unknown): void {
  if (typeof value !== "string" || !/^[0-9a-fA-F]{6}$/.test(value))
    throw new Error("Invalid drawing color");
}

export function drawingBatch(value: unknown): DrawingBatch {
  const batch = record(value);
  if (
    !Array.isArray(batch.outlines) ||
    !Array.isArray(batch.images) ||
    !Array.isArray(batch.pages) ||
    batch.pages.length === 0 ||
    batch.pages.length > 1024 ||
    batch.images.length > 256
  )
    throw new Error("Invalid drawing batch");
  const outlines = new Set<string>();
  let pathUnits = 0;
  for (const value of batch.outlines) {
    const outline = record(value);
    if (
      typeof outline.key !== "string" ||
      !outline.key ||
      outlines.has(outline.key) ||
      typeof outline.path !== "string"
    )
      throw new Error("Invalid drawing outline");
    pathUnits += outline.path.length;
    if (pathUnits > 8388608) throw new Error("Drawing outlines exceed budget");
    outlines.add(outline.key);
  }
  const images = new Set<string>();
  for (const key of batch.images) {
    if (typeof key !== "string" || !key || images.has(key))
      throw new Error("Invalid drawing image resource");
    images.add(key);
  }
  for (const value of batch.pages) {
    const page = record(value);
    if (
      finite(page.width) <= 0 ||
      finite(page.width) > 14400 ||
      finite(page.height) <= 0 ||
      finite(page.height) > 14400 ||
      !Array.isArray(page.commands)
    )
      throw new Error("Invalid drawing region");
    let clips = 0;
    for (const value of page.commands) {
      const command = record(value);
      switch (command.op) {
        case "fillRect":
          rect(command.rect);
          color(record(command.rect).color);
          break;
        case "strokeRect":
          rect(command.rect);
          color(command.color);
          if (finite(command.lineWidth) <= 0)
            throw new Error("Invalid drawing line width");
          break;
        case "glyphs":
          color(command.color);
          finite(command.x);
          finite(command.y);
          if (!Array.isArray(command.glyphs))
            throw new Error("Invalid drawing glyph batch");
          for (const value of command.glyphs) {
            const glyph = record(value);
            if (
              typeof glyph.outline !== "string" ||
              !outlines.has(glyph.outline)
            )
              throw new Error("Missing drawing outline");
            finite(glyph.x);
            finite(glyph.y);
            finite(glyph.scaleX);
            finite(glyph.scaleY);
          }
          break;
        case "image": {
          rect(command.image);
          const image = record(command.image);
          if (typeof image.key !== "string" || !images.has(image.key))
            throw new Error("Missing drawing image");
          break;
        }
        case "clipRect":
          rect(command.rect);
          clips++;
          break;
        case "restoreClip":
          if (--clips < 0) throw new Error("Invalid drawing clip stack");
          break;
        default:
          throw new Error(`Unknown drawing command: ${String(command.op)}`);
      }
    }
    if (clips !== 0) throw new Error("Unclosed drawing clip");
  }
  return value as DrawingBatch;
}
