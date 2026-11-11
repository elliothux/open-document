export interface DocxPosition {
  paragraph: number;
  offset: number;
  affinity: "before" | "after";
  bidiLevel?: number;
  /** Start offset of the retained follow frame; editing still uses offset. */
  frameStart?: number;
}

export interface DocxSelection {
  anchor: DocxPosition;
  focus: DocxPosition;
}

export interface DocxHit {
  layoutId: number;
  revision: number;
  page: number;
  line: number;
  position: DocxPosition | null;
  /** Exact logical drawing range; the pointer's nearest text edge remains position. */
  drawing: DocxSelection | null;
  editable: boolean;
  reason: string;
  x: number;
  y: number;
  height: number;
}

export interface DocxSelectionGeometry {
  layoutId: number;
  revision: number;
  rects: {
    page: number;
    line: number;
    x: number;
    y: number;
    width: number;
    height: number;
  }[];
}
import type { DocxFormatting } from "./docx-format.js";

export interface DocxSelectionViewRequest {
  revision: number;
  selection: DocxSelection;
  formatTable: boolean;
  describeText: boolean;
}

export interface DocxSelectionView {
  layoutId: number;
  revision: number;
  caret: DocxHit;
  geometry: DocxSelectionGeometry;
  formatting: DocxFormatting | null;
  selectedText: string;
  selectionError: string;
}
