import type { DrawRect, DrawMatrix } from "./drawing.js";
import type {
  PptxHyperlink,
  PptxCap,
  PptxJoin,
  PptxLineEnd,
  PptxDash,
} from "./pptx-objects.js";
import type { PptxBackgroundFill } from "./pptx-slides.js";
import type { PptxPlaceholder } from "./pptx-placeholder.js";

export interface PptxObject {
  id: string;
  parent: string;
  name: string;
  kind: string;
  text: string;
  readOnlyReason: string;
  textReadOnlyReason: string;
  deleteReason: string;
  duplicateReason: string;
  rotateReason: string;
  arrangeReason: string;
  transformReason: string;
  placeholder: { value: PptxPlaceholder | null; reason: string };
  hyperlink: { value: PptxHyperlink | null; reason: string };
  shapeAdjustments: {
    preset: string;
    reason: string;
    values: { name: "adj" | "adj1" | "adj2"; value: number; maximum: number }[];
  };
  imageInsets: [number, number, number, number];
  imageInsetsReason: string;
  picture: {
    mode: "stretch" | "tile";
    modeReason: string;
    opacity: number;
    opacityReason: string;
    left: number;
    top: number;
    right: number;
    bottom: number;
    replaceReason: string;
    cropReason: string;
  };
  appearance: {
    imageFill: string | null;
    imageFillMode: "stretch" | "tile" | null;
    imageFillReason: string;
    gradient: Extract<PptxBackgroundFill, { kind: "linear" }> | null;
    fillOpacity: number;
    strokeOpacity: number;
    fillOpacityReason: string;
    strokeOpacityReason: string;
    cap: PptxCap;
    join: PptxJoin;
    miterLimit: number;
    penReason: string;
    headEnd: PptxLineEnd;
    tailEnd: PptxLineEnd;
    lineEndReason: string;
    dash: PptxDash;
    dashReason: string;
    fill: string | null;
    stroke: string | null;
    width: number;
    reason: string;
  };
  textFrame: {
    left: number;
    top: number;
    right: number;
    bottom: number;
    anchor: string;
    wrap: boolean;
    fit: "none" | "shrink" | "resize";
    reason: string;
  };
  geometry:
    | (DrawRect & {
        matrix: DrawMatrix;
        rotation: number;
        flipX: boolean;
        flipY: boolean;
      })
    | null;
}
