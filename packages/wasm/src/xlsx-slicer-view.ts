import { integer, record } from "./validation.js";
import {
  checkDrawingFrameView,
  type XlsxDrawingFrame,
} from "./xlsx-drawing-frame.js";
import {
  drawingRegions,
  type XlsxDrawingRegion,
} from "./xlsx-drawing-pointer.js";

export interface XlsxSlicerView {
  name: string;
  caption: string;
  frame: XlsxDrawingFrame;
  move: XlsxDrawingRegion[];
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
}

export function checkSlicerView(value: unknown): void {
  const view = record(value);
  checkDrawingFrameView(view.frame);
  if (
    typeof view.name !== "string" ||
    !view.name.trim() ||
    view.name.length > 255 ||
    typeof view.caption !== "string" ||
    view.caption.length > 255 ||
    !integer(view.start, 0, 4095) ||
    !integer(view.maximum, 0, 4095) ||
    !integer(view.page, 1, 4096) ||
    !Array.isArray(view.buttons) ||
    view.buttons.length > 4096
  )
    throw new Error("Invalid slicer view");
  for (const key of ["move", "clear", "multi", "previous", "next"])
    drawingRegions(view[key]);
  const indices = new Set<number>();
  let units = 0;
  for (const value of view.buttons) {
    const button = record(value);
    if (
      typeof button.index !== "number" ||
      !integer(button.index, 0, 4095) ||
      indices.has(button.index) ||
      typeof button.label !== "string" ||
      !button.label.isWellFormed() ||
      typeof button.selected !== "boolean" ||
      typeof button.hasData !== "boolean"
    )
      throw new Error("Invalid visible slicer member");
    drawingRegions(button.regions);
    indices.add(button.index);
    units += button.label.length;
    if (units > 1048576) throw new Error("Visible slicer text exceeds budget");
  }
}
