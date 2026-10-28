import type { DocxInkStroke } from "../core/foundation.js";

export type DocxInkRequest = {
  operation: "docxInk";
  revision: number;
  layoutId: number;
  page: number;
} & (
  | { action: "preview"; stroke: DocxInkStroke }
  | { action: "insert"; stroke: DocxInkStroke; profile: Record<string, string> }
  | { action: "erase"; x: number; y: number }
);
