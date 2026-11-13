import { record } from "./validation.js";
import { gradientStopCount } from "@open-document/wasm/engine-source";

export type RasterHeader =
  | {
      width: number;
      height: number;
      allowTranspose?: true;
      coreVerified?: true;
    }
  | { error: string };

export interface EncodedImage<Bytes = Uint8Array> {
  kind: "encoded";
  bytes: Bytes;
  header: RasterHeader;
}

export type ImagePreparation<Bytes = Uint8Array> =
  | EncodedImage<Bytes>
  | { kind: "rgba"; key: string; width: number; height: number; bytes: Bytes };

export interface DrawRect {
  x: number;
  y: number;
  width: number;
  height: number;
}

export type ClipBounds = [
  left: number,
  top: number,
  right: number,
  bottom: number,
];

export interface GradientStop {
  position: number;
  color: string;
  opacity: number;
}

export function checkGradientStops(
  value: unknown,
): asserts value is GradientStop[] {
  if (
    !Array.isArray(value) ||
    value.length < 2 ||
    value.length > gradientStopCount
  )
    throw new Error("Gradients require 2..32 stops");
  let previous = 0;
  for (const item of value) {
    const stop = record(item);
    if (
      Object.keys(stop).length !== 3 ||
      Object.keys(stop).some(
        (key) => !["position", "color", "opacity"].includes(key),
      ) ||
      typeof stop.opacity !== "number" ||
      !Number.isFinite(stop.opacity) ||
      stop.opacity < 0 ||
      stop.opacity > 1 ||
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

export type DrawGlyphRun<Outline extends string | number = string> = [
  upem: number,
  fontBounds: [number, number, number, number] | null,
  strokeWidth: number,
  scaleX: number,
  scaleY: number,
  glyphs: [outline: Outline, x: number, y: number][],
];

export interface PdfGlyphCommand {
  op: "pdfGlyphs";
  color: string;
  matrix: [a: number, b: number, c: number, d: number];
  origin: [x: number, y: number];
  outlines: string[];
  /** Each glyph position is the translation of the shared matrix. */
  run: DrawGlyphRun<number>;
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

export type StrokeGeometry =
  "segments" | "rectangles" | "openRectangle" | "closed" | "curve";

export type RectangleDashSpan = [
  edge: number,
  length: number,
  start: number,
  end: number,
  join: boolean,
];

export interface GradientClip {
  axial?: {
    transforms: DrawMatrix[];
    startX: number;
    endX: number;
    y: number;
    startBounded: boolean;
    endBounded: boolean;
  };
}

export type DrawCommand =
  | {
      op: "tile";
      width: number;
      height: number;
      columns: number;
      rows: number;
      matrix: DrawMatrix;
      resolution: { x: number; y: number };
      commands: DrawCommand[];
      replay?: true;
    }
  | { op: "layer"; opacity: number; commands: DrawCommand[] }
  | {
      op: "mask";
      mask: DrawCommand[];
      commands: DrawCommand[];
      luminosity?: true;
    }
  | { op: "style"; style: DrawStyle }
  // Scoped by transform/clip restores; vector paths use device pixel centers.
  | { op: "pixelCenters" }
  | { op: "integerScreenGlyphs" }
  | ({
      op: "clipPath";
      evenOdd: boolean;
      shading?: GradientClip;
    } & ({ path: PathSegment[] } | { rectangle: ClipBounds }))
  | {
      op: "fillRect";
      rect: DrawRect & { color: string };
      screenFractional?: true;
    }
  | { op: "gradientRect"; rect: DrawRect; stops: GradientStop[] }
  | {
      op: "radialGradientRect";
      rect: DrawRect;
      stops: GradientStop[];
      circles: [number, number, number, number, number, number];
    }
  | {
      op: "patternRect";
      rect: DrawRect;
      period: number;
      mask: number[];
      zero: string;
      one: string;
      screenDevice?: boolean;
    }
  | {
      op: "strokeRect";
      rect: DrawRect;
      color: string;
      lineWidth: number;
      screenFractional?: true;
    }
  | { op: "glyphs"; x: number; y: number; color: string; runs: DrawGlyphRun[] }
  | PdfGlyphCommand
  | {
      op: "strokeBands";
      color: string;
      lineWidth: number;
      bands: [y: number, height: number, spans: [x: number, width: number][]][];
    }
  | {
      op: "image";
      image: DrawRect & { key: string; interpolate: boolean | null };
      preservePixels?: true;
      crop?: { clip: DrawRect; visible: DrawRect };
    }
  | {
      op: "path";
      path: PathSegment[];
      fill: string;
      stroke: string;
      lineWidth: number;
      strokeGeometry?: StrokeGeometry | undefined;
      strokeNonRectangular?: true;
      strokeOutline?: PathSegment[] | undefined;
      strokeBounds?: ClipBounds;
      strokeDashes?: [number, number][][] | undefined;
      strokeDashesAxisAligned?: boolean;
      rectangleDashes?: RectangleDashSpan[];
      textRule?: true;
    }
  | { op: "transform"; matrix: DrawMatrix }
  | { op: "clipRect"; rect: DrawRect; shading?: GradientClip }
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
  blend:
    | "normal"
    | "multiply"
    | "difference"
    | "overlay"
    | "darken"
    | "soft-light"
    | "color";
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
  backingClip?: true;
  deviceClips?: true;
  imageSampling?: "coverage";
  strokeRaster?: "integer" | "fractional" | "coverage";
  glyphRaster?: "integer" | "fractional" | "coverage";
  commands: DrawCommand[];
}
