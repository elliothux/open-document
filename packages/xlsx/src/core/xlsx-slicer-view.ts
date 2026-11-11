import type { XlsxDrawingFrame } from "./xlsx-drawing-frame.js";
import type { XlsxDrawingRegion } from "./xlsx-drawing-pointer.js";

export interface XlsxSlicerView {
  name: string;
  caption: string;
  frame: XlsxDrawingFrame;
  move: XlsxDrawingRegion[];
  /** Zero-based visible row and final scrollable row. */
  start: number;
  maximum: number;
  page: number;
  buttons: {
    index: number;
    label: string;
    selected: boolean;
    hasData: boolean;
    regions: XlsxDrawingRegion[];
  }[];
  clear: XlsxDrawingRegion[];
  multi: XlsxDrawingRegion[];
  previous: XlsxDrawingRegion[];
  next: XlsxDrawingRegion[];
  scroll: XlsxDrawingRegion[];
}
