import { record } from "./validation.js";

export interface DrawRect {
  x: number;
  y: number;
  width: number;
  height: number;
}

export interface GradientStop {
  position: number;
  color: string;
}

export function checkGradientStops(
  value: unknown,
): asserts value is GradientStop[] {
  if (!Array.isArray(value) || value.length < 2 || value.length > 32)
    throw new Error("Gradients require 2..32 stops");
  let previous = 0;
  for (const item of value) {
    const stop = record(item);
    if (
      Object.keys(stop).length !== 2 ||
      Object.keys(stop).some((key) => !["position", "color"].includes(key)) ||
      typeof stop.position !== "number" ||
      !Number.isFinite(stop.position) ||
      stop.position < previous ||
      stop.position > 1 ||
      typeof stop.color !== "string" ||
      !/^[0-9a-f]{6}$/iu.test(stop.color)
    )
      throw new Error("Invalid ordered gradient stop");
    previous = stop.position;
  }
}

export interface DrawGlyph {
  outline: string;
  x: number;
  y: number;
  scaleX: number;
  scaleY: number;
}

export interface DrawMatrix {
  a: number;
  b: number;
  c: number;
  d: number;
  e: number;
  f: number;
}

export type PathSegment =
  | { op: "move" | "line"; x: number; y: number }
  | {
      op: "cubic";
      x1: number;
      y1: number;
      x2: number;
      y2: number;
      x: number;
      y: number;
    }
  | { op: "close" };

export type DrawCommand =
  | { op: "style"; style: DrawStyle }
  | { op: "clipPath"; path: PathSegment[]; evenOdd: boolean }
  | { op: "fillRect"; rect: DrawRect & { color: string } }
  | { op: "gradientRect"; rect: DrawRect; stops: GradientStop[] }
  | { op: "strokeRect"; rect: DrawRect; color: string; lineWidth: number }
  | { op: "glyphs"; x: number; y: number; color: string; glyphs: DrawGlyph[] }
  | { op: "image"; image: DrawRect & { key: string } }
  | {
      op: "path";
      path: PathSegment[];
      fill: string;
      stroke: string;
      lineWidth: number;
    }
  | { op: "transform"; matrix: DrawMatrix }
  | { op: "clipRect"; rect: DrawRect }
  | { op: "restore" };

export interface DrawStyle {
  fillAlpha: number;
  strokeAlpha: number;
  evenOdd: boolean;
  cap: number;
  join: number;
  miter: number;
  dash: number[];
  dashOffset: number;
  multiply: boolean;
  imageSmoothing: boolean;
}

/** Platform-independent drawing, with resources shared across regions. */
export interface DrawingBatch {
  regions: DrawingRegion[];
  outlines: { key: string; path: string }[];
  images: string[];
}

export interface DrawingRegion {
  width: number;
  height: number;
  commands: DrawCommand[];
}

function finite(value: unknown): number {
  if (
    typeof value !== "number" ||
    !Number.isFinite(value) ||
    Math.abs(value) > 1e9
  )
    throw new Error("Invalid drawing number");
  return value;
}

export function drawingMatrix(value: unknown): DrawMatrix {
  const matrix = record(value);
  for (const key of ["a", "b", "c", "d", "e", "f"]) finite(matrix[key]);
  const a = finite(matrix.a),
    b = finite(matrix.b),
    c = finite(matrix.c),
    d = finite(matrix.d);
  if (Math.abs(a * d - b * c) < 1e-9)
    throw new Error("Noninvertible drawing matrix");
  return value as DrawMatrix;
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
    !Array.isArray(batch.regions) ||
    batch.regions.length === 0 ||
    batch.regions.length > 1024 ||
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
  let payload = 0;
  for (const value of batch.regions) {
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
      if (++payload > 1048576)
        throw new Error("Drawing payload exceeds budget");
      const command = record(value);
      switch (command.op) {
        case "fillRect":
          rect(command.rect);
          color(record(command.rect).color);
          break;
        case "gradientRect":
          rect(command.rect);
          checkGradientStops(command.stops);
          payload += command.stops.length;
          if (payload > 1048576)
            throw new Error("Drawing payload exceeds budget");
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
            if (++payload > 1048576)
              throw new Error("Drawing glyphs exceed budget");
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
        case "style": {
          const style = record(command.style);
          for (const key of ["fillAlpha", "strokeAlpha"]) {
            const alpha = finite(style[key]);
            if (alpha < 0 || alpha > 1)
              throw new Error("Invalid drawing alpha");
          }
          if (
            ![0, 1, 2].includes(finite(style.cap)) ||
            ![0, 1, 2].includes(finite(style.join)) ||
            finite(style.miter) < 1 ||
            typeof style.evenOdd !== "boolean" ||
            typeof style.multiply !== "boolean" ||
            typeof style.imageSmoothing !== "boolean" ||
            !Array.isArray(style.dash) ||
            style.dash.length > 256
          )
            throw new Error("Invalid drawing style");
          finite(style.dashOffset);
          for (const item of style.dash)
            if (finite(item) < 0) throw new Error("Invalid drawing dash");
          if (style.dash.length && style.dash.every((item) => item === 0))
            throw new Error("Empty drawing dash");
          break;
        }
        case "clipPath":
        case "path": {
          if (command.op === "path") {
            if (command.fill !== "") color(command.fill);
            if (command.stroke !== "") color(command.stroke);
            if (finite(command.lineWidth) < 0)
              throw new Error("Invalid drawing width");
          } else {
            if (typeof command.evenOdd !== "boolean" || ++clips > 32)
              throw new Error("Invalid drawing clip");
          }
          if (
            !Array.isArray(command.path) ||
            (command.op === "path" && command.path.length === 0) ||
            (command.path.length > 0 && record(command.path[0]).op !== "move")
          )
            throw new Error("Invalid drawing path");
          for (const value of command.path) {
            if (++payload > 1048576)
              throw new Error("Drawing path exceeds budget");
            const segment = record(value);
            if (segment.op === "close") continue;
            if (!["move", "line", "cubic"].includes(String(segment.op)))
              throw new Error("Unknown path operation");
            finite(segment.x);
            finite(segment.y);
            if (segment.op === "cubic")
              for (const key of ["x1", "y1", "x2", "y2"]) finite(segment[key]);
          }
          break;
        }
        case "transform":
          drawingMatrix(command.matrix);
          if (++clips > 32) throw new Error("Drawing nesting exceeds budget");
          break;
        case "clipRect":
          rect(command.rect);
          if (++clips > 32) throw new Error("Drawing nesting exceeds budget");
          break;
        case "restore":
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
