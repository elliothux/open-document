import type { CellRange, XlsxCell } from "./xlsx.js";
import type { XlsxShapeKind } from "./xlsx-shapes.js";
import {
  type DrawingBatch,
  type DrawRect,
} from "@open-document/wasm/abi/drawing";
import { record } from "@open-document/wasm/abi/validation";
import type { XlsxSlicerView } from "./xlsx-slicer-view.js";
import type { XlsxTimelineView } from "./xlsx-timeline.js";
import type { XlsxDrawingRegion } from "./xlsx-drawing-pointer.js";

export interface XlsxViewport extends DrawingBatch {
  id: number;
  revision: number;
  sheet: string;
  scrollX: number;
  scrollY: number;
  extentWidth: number;
  extentHeight: number;
  headerWidth: number;
  headerHeight: number;
  rtl: boolean;
  cells: {
    cell: XlsxCell;
    display: string;
    accessibleText?: string;
    rect: DrawRect;
    clip: DrawRect;
    range: CellRange;
    diagnostic: string;
  }[];
  notes: { address: string; author: string; text: string; rect: DrawRect }[];
  objects: {
    id: string;
    kind: "picture" | "chart" | "slicer" | "timeline" | XlsxShapeKind;
    name: string;
    selected: boolean;
    regions: XlsxDrawingRegion[];
    slicer?: XlsxSlicerView;
    timeline?: XlsxTimelineView;
  }[];
  rows: { index: number; position: number; size: number }[];
  columns: XlsxViewport["rows"];
  diagnostics: string[];
}

type GridBounds = [number, number, number, number];
type BlankGridCell = [
  address: string,
  row: number,
  column: number,
  style: number,
  reason: string,
];
type CompactGridCell = [
  cell: XlsxCell | BlankGridCell,
  display: string,
  rect: GridBounds,
  range: GridBounds | null,
  diagnostic: string,
  clip: number,
  accessibleText: string | null,
];

export type CompactXlsxViewport = Omit<XlsxViewport, "cells"> & {
  cellClips: GridBounds[];
  cells: CompactGridCell[];
};

function gridRect([x, y, width, height]: GridBounds): DrawRect {
  return { x, y, width, height };
}

function blankGridCell([
  address,
  row,
  column,
  style,
  readOnlyReason,
]: BlankGridCell): XlsxCell {
  return {
    address,
    row,
    column,
    style,
    value: { kind: "blank", value: null },
    input: "",
    formula: null,
    cached: null,
    calculated: null,
    calculation: "value",
    calculationReason: "",
    display: "",
    readOnlyReason,
  };
}

export function expandXlsxViewport({
  cellClips,
  cells,
  ...viewport
}: CompactXlsxViewport): XlsxViewport {
  return {
    ...viewport,
    cells: cells.map(
      ([source, display, rect, range, diagnostic, clip, accessibleText]) => {
        const cell = "address" in source ? source : blankGridCell(source);
        const [top, left, bottom, right] = range ?? [
          cell.row,
          cell.column,
          cell.row,
          cell.column,
        ];
        return {
          cell,
          display,
          rect: gridRect(rect),
          range: { top, left, bottom, right },
          diagnostic,
          ...(accessibleText === null ? {} : { accessibleText }),
          clip: gridRect(cellClips[clip]!),
        };
      },
    ),
  };
}

export function cellValue(value: unknown): boolean {
  const item = record(value);
  switch (item.kind) {
    case "blank":
      return item.value === null;
    case "text":
    case "error":
      return typeof item.value === "string";
    case "number":
      return typeof item.value === "number" && Number.isFinite(item.value);
    case "boolean":
      return typeof item.value === "boolean";
    default:
      return false;
  }
}

export interface XlsxPrintLayout extends DrawingBatch {
  id: number;
  revision: number;
  sheet: string;
}
