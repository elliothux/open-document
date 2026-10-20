import { checkPptxConnectorEdit } from "./pptx-connectors.js";
import { record } from "./validation.js";
import { pptxInsertKinds } from "./pptx-object-edit.js";
import { checkPptxChartEdit } from "./pptx-chart.js";
import { checkPptxMediaInput, checkMediaPlayback } from "./pptx-media.js";
import { pptxPlaceholder, pptxPlaceholderTypes } from "./pptx-placeholder.js";
import { drawingMatrix } from "./drawing.js";
import {
  checkPptxSpacing,
  checkPptxSizeMatches,
  type PptxGuide,
  type PptxSpacing,
  type PptxSizeMatch,
} from "./pptx-view.js";
import {
  checkPptxTableStyle,
  checkPptxTableStyleQuery,
  type PptxTableStyleQuery,
} from "./pptx-table-style.js";
export type { PptxTableStyle } from "./pptx-table-style.js";

export interface PptxSelection {
  slide: string;
  object: string;
  objects: string[];
  mode: "object" | "text";
  anchor: number;
  focus: number;
}
export interface PptxPoint {
  x: number;
  y: number;
}
export interface PptxGeometry {
  snapSize: PptxSizeMatch[];
  snapSpacing: PptxSpacing[];
  snapLines: PptxGuide[];
  grid: { points: PptxPoint[]; cross: boolean } | null;
  layoutId: number;
  revision: number;
  outline: PptxPoint[];
  outlines: PptxPoint[][];
  handles: PptxPoint[];
  rects: PptxPoint[][];
  caret: (PptxPoint & { endX: number; endY: number; height: number }) | null;
}
export interface PptxHit {
  object: string;
  offset: number;
  readOnlyReason: string;
  textReadOnlyReason: string;
}
export interface PptxTable {
  style: PptxTableStyleQuery;
  object: string;
  rows: number;
  columns: number;
  row: number;
  column: number;
  firstRow: number;
  lastRow: number;
  firstColumn: number;
  lastColumn: number;
  rowHeight: number | null;
  columnWidth: number | null;
  reason: string;
  splitReason: string;
  operations: Record<(typeof tableOperations)[number], string>;
  format: {
    fill: string | null;
    borderColor: string | null;
    borderWidth: number | null;
    left: number | null;
    top: number | null;
    right: number | null;
    bottom: number | null;
    anchor: "t" | "ctr" | "b" | null;
    reason: string;
    borderReason: string;
  };
}
const tableOperations = [
  "insertRowBefore",
  "insertRowAfter",
  "deleteRow",
  "insertColumnBefore",
  "insertColumnAfter",
  "deleteColumn",
  "merge",
  "unmerge",
] as const;

export function checkPptxTable(
  value: unknown,
  selected: readonly string[],
  active: unknown,
): void {
  if (value === null) return;
  const table = record(value),
    rows = number(table.rows, 1, 1000),
    columns = number(table.columns, 1, 63);
  const operations = record(table.operations);
  checkPptxTableStyleQuery(table.style);
  for (const key of ["rowHeight", "columnWidth"])
    if (table[key] !== null) number(table[key], 1 / 12700, 14400);
  const format = record(table.format);
  for (const key of ["fill", "borderColor"]) {
    const value = format[key];
    if (
      value !== null &&
      (typeof value !== "string" ||
        (value !== "" && !/^[0-9a-f]{6}$/i.test(value)))
    )
      throw new Error("Invalid PPTX cell color");
  }
  for (const key of ["left", "top", "right", "bottom", "borderWidth"])
    if (format[key] !== null)
      number(format[key], 0, key === "borderWidth" ? 1000 : 14400);
  if (
    ![null, "t", "ctr", "b"].some((value) => value === format.anchor) ||
    typeof format.reason !== "string" ||
    typeof format.borderReason !== "string"
  )
    throw new Error("Invalid PPTX cell format");
  if (
    Object.keys(operations).length !== tableOperations.length ||
    tableOperations.some(
      (operation) => typeof operations[operation] !== "string",
    )
  )
    throw new Error("Invalid PPTX table operation reasons");
  const row = number(table.row, 0, rows - 1),
    column = number(table.column, 0, columns - 1);
  const firstRow = number(table.firstRow, 0, rows - 1),
    lastRow = number(table.lastRow, firstRow, rows - 1),
    firstColumn = number(table.firstColumn, 0, columns - 1),
    lastColumn = number(table.lastColumn, firstColumn, columns - 1);
  if (
    ![
      rows,
      columns,
      row,
      column,
      firstRow,
      lastRow,
      firstColumn,
      lastColumn,
    ].every(Number.isInteger) ||
    row < firstRow ||
    row > lastRow ||
    column < firstColumn ||
    column > lastColumn ||
    rows * columns > 4096 ||
    typeof table.object !== "string" ||
    !table.object ||
    table.object !== active ||
    selected.length !== 1 ||
    selected[0] !== table.object ||
    typeof table.reason !== "string" ||
    typeof table.splitReason !== "string"
  )
    throw new Error("Invalid PPTX table query");
}

export function imageInsets(value: unknown): void {
  if (
    !Array.isArray(value) ||
    value.length !== 4 ||
    value.some(
      (v) =>
        typeof v !== "number" ||
        !Number.isFinite(v) ||
        v < -21474.83648 ||
        v > 21474.83647,
    )
  )
    throw new Error("Invalid image destination insets");
  const values = value.map((v) => Math.round(v * 100000));
  if (values[0]! + values[2]! >= 100000 || values[1]! + values[3]! >= 100000)
    throw new Error("Image destination must retain positive area");
}

export function strings(value: unknown, count: number, units: number): void {
  if (
    !Array.isArray(value) ||
    value.length > count ||
    value.some((item) => typeof item !== "string" || item.length > units)
  )
    throw new Error("Invalid PPTX string array");
}
export function geometry(value: unknown): void {
  const rect = record(value);
  number(rect.x, -14400, 14400);
  number(rect.y, -14400, 14400);
  number(rect.width, 0, 14400);
  number(rect.height, 0, 14400);
  number(rect.rotation, -360, 360);
  if (typeof rect.flipX !== "boolean" || typeof rect.flipY !== "boolean")
    throw new Error("Invalid PPTX orientation");
  drawingMatrix(rect.matrix);
}
export function points(value: unknown, max = 4): void {
  if (!Array.isArray(value) || value.length > max)
    throw new Error("Invalid PPTX polygon");
  for (const point of value) {
    const p = record(point);
    number(p.x, -1e9, 1e9);
    number(p.y, -1e9, 1e9);
  }
}
export function checkPptxGeometry(value: unknown): void {
  const selection = record(value);
  checkPptxSpacing(selection.snapSpacing);
  checkPptxSizeMatches(selection.snapSize);
  if (!Array.isArray(selection.snapLines) || selection.snapLines.length > 128)
    throw new Error("Invalid PPTX alignment marks");
  for (const item of selection.snapLines) {
    const line = record(item);
    if (
      Object.keys(line).length !== 2 ||
      (line.orientation !== "vert" && line.orientation !== "horz")
    )
      throw new Error("Invalid PPTX alignment line");
    number(line.position, 0, 14400);
  }
  for (const key of ["layoutId", "revision"])
    if (!Number.isInteger(number(selection[key], 0, 0x7fffffff)))
      throw new Error("Invalid PPTX geometry identity");
  points(selection.outline);
  points(selection.handles);
  if (!Array.isArray(selection.outlines) || selection.outlines.length > 256)
    throw new Error("Invalid PPTX object outlines");
  for (const outline of selection.outlines) points(outline);
  if (!Array.isArray(selection.rects) || selection.rects.length > 32767)
    throw new Error("Invalid PPTX selection rectangles");
  for (const rect of selection.rects) points(rect);
  if (selection.caret !== null) {
    const caret = record(selection.caret);
    for (const key of ["x", "y", "endX", "endY"]) number(caret[key], -1e9, 1e9);
    number(caret.height, 0, 14400);
  }
  if (selection.grid !== null) {
    const grid = record(selection.grid);
    if (
      Object.keys(grid).length !== 2 ||
      typeof grid.cross !== "boolean" ||
      !Array.isArray(grid.points) ||
      grid.points.length > 16384
    )
      throw new Error("Invalid PPTX grid marks");
    for (const point of grid.points) {
      const p = record(point);
      number(p.x, 0, 14400);
      number(p.y, 0, 14400);
    }
  }
}
import { checkPptxBackgroundFill } from "./pptx-slides.js";
import {
  checkPptxTextFormat,
  checkPptxParagraphFormat,
} from "./pptx-format.js";
export const pptxDashes = [
  "solid",
  "dash",
  "dashDot",
  "dot",
  "lgDash",
  "lgDashDot",
  "lgDashDotDot",
  "sysDash",
  "sysDashDot",
  "sysDashDotDot",
  "sysDot",
] as const;
export function checkPptxImageFill(
  appearance: Record<string, unknown>,
  kind: unknown,
): void {
  if (
    appearance.imageFill === null
      ? appearance.imageFillMode !== null
      : appearance.imageFillMode !== "stretch" &&
        appearance.imageFillMode !== "tile"
  )
    throw new Error("Invalid image fill mode query");
  if (
    appearance.imageFill !== null &&
    (typeof appearance.imageFill !== "string" ||
      !appearance.imageFill ||
      appearance.imageFill.length > 256 ||
      kind !== "shape" ||
      appearance.fill !== null ||
      appearance.gradient !== null)
  )
    throw new Error("Invalid image fill appearance");
}
export type PptxDash = (typeof pptxDashes)[number];
export const pptxCaps = ["flat", "rnd", "sq"] as const;
export const pptxJoins = ["round", "bevel", "miter"] as const;
export type PptxCap = (typeof pptxCaps)[number];
export type PptxJoin = (typeof pptxJoins)[number];
export interface PptxLineEnd {
  kind: "none" | "triangle" | "stealth" | "diamond" | "oval" | "arrow";
  width: "sm" | "med" | "lg";
  length: "sm" | "med" | "lg";
}
export function checkPptxLineEnd(value: unknown): void {
  const end = record(value);
  if (
    typeof end.kind !== "string" ||
    !["none", "triangle", "stealth", "diamond", "oval", "arrow"].includes(
      end.kind,
    ) ||
    typeof end.width !== "string" ||
    !["sm", "med", "lg"].includes(end.width) ||
    typeof end.length !== "string" ||
    !["sm", "med", "lg"].includes(end.length) ||
    Object.keys(end).some((key) => !["kind", "width", "length"].includes(key))
  )
    throw new Error("Invalid PPTX line end");
}
export type PptxHyperlink =
  | { kind: "external" | "slide"; target: string }
  | {
      kind: "action";
      target:
        | "firstslide"
        | "lastslide"
        | "nextslide"
        | "previousslide"
        | "lastslideviewed"
        | "endshow";
    };

export function pptxHyperlink(value: unknown): PptxHyperlink | null {
  if (value === null) return null;
  const link = record(value);
  if (
    (link.kind !== "external" &&
      link.kind !== "slide" &&
      link.kind !== "action") ||
    typeof link.target !== "string" ||
    !link.target.isWellFormed() ||
    !link.target ||
    link.target.length > (link.kind === "slide" ? 1024 : 2048) ||
    Object.keys(link).some((key) => key !== "kind" && key !== "target") ||
    (link.kind === "action" &&
      ![
        "firstslide",
        "lastslide",
        "nextslide",
        "previousslide",
        "lastslideviewed",
        "endshow",
      ].includes(link.target)) ||
    (link.kind === "external" &&
      (!/^(https?:\/\/|mailto:).+/i.test(link.target) ||
        /\s/u.test(link.target) ||
        Array.from(link.target).some(
          (c) => c.charCodeAt(0) <= 32 || c.charCodeAt(0) === 127 || c === "\\",
        )))
  )
    throw new Error("Invalid PPTX hyperlink");
  return value as PptxHyperlink;
}
export type { PptxObjectEdit } from "./pptx-object-edit.js";

export function number(value: unknown, low = 0, high = 0x7fffffff): number {
  if (
    typeof value !== "number" ||
    !Number.isFinite(value) ||
    value < low ||
    value > high
  )
    throw new Error("Invalid PPTX number");
  return value;
}
export function checkPptxObjectEdit(value: unknown): void {
  const change = record(value);
  if (checkPptxChartEdit(value)) return;
  if (change.action === "insertWordArt") {
    const text = objectText(change.text);
    if (
      Object.keys(change).length !== 3 ||
      Object.keys(change).some(
        (key) => !["action", "preset", "text"].includes(key),
      ) ||
      !["blue", "gold", "red", "purple", "green-italic"].some(
        (preset) => preset === change.preset,
      ) ||
      !text.trim()
    )
      throw new Error("Invalid solid WordArt preset or text");
    return;
  }
  if (change.action === "mediaPlayback") {
    if (Object.keys(change).length !== 2)
      throw new Error("Invalid media playback change");
    checkMediaPlayback(change.value);
    return;
  }
  if (change.action === "insertMedia") {
    checkPptxMediaInput(value);
    return;
  }
  if (change.action === "insertDiagram") {
    number(change.x, -14400, 14400);
    number(change.y, -14400, 14400);
    number(change.width, 0.1, 14400);
    number(change.height, 0.1, 14400);
    if (
      !["process", "hierarchy", "cycle"].some(
        (template) => template === change.template,
      ) ||
      !Array.isArray(change.items) ||
      change.items.length < (change.template === "cycle" ? 3 : 2) ||
      change.items.length > 16 ||
      Object.keys(change).some(
        (key) =>
          ![
            "action",
            "template",
            "items",
            "x",
            "y",
            "width",
            "height",
          ].includes(key),
      )
    )
      throw new Error("Invalid diagram template or labels");
    const items: unknown[] = change.items;
    let units = 0;
    for (const item of items) {
      if (typeof item !== "string" || item.length > 4096)
        throw new Error("Invalid diagram label");
      units += item.length;
    }
    if (units > 32767) throw new Error("Diagram labels exceed budget");
    return;
  }
  if (
    change.action === "insertConnector" ||
    change.action === "connectorEndpoints"
  ) {
    checkPptxConnectorEdit(change);
    return;
  }
  if (change.action === "placeholder") {
    if (Object.keys(change).length !== 2)
      throw new Error("Invalid placeholder edit");
    pptxPlaceholder(change.value);
    return;
  }
  if (change.action === "tableStyle") {
    checkPptxTableStyle(change.style);
    if (Object.keys(change).some((key) => key !== "action" && key !== "style"))
      throw new Error("Invalid PPTX table style command");
    return;
  }
  if (
    change.action === "tableRowHeight" ||
    change.action === "tableColumnWidth"
  ) {
    number(change.value, 0.1, 14400);
    if (Object.keys(change).some((key) => key !== "action" && key !== "value"))
      throw new Error("Invalid PPTX table dimension");
    return;
  }
  if (change.action === "splitTableCell" || change.action === "fillTable") {
    const rows = number(change.rows, 1, 1000),
      columns = number(change.columns, 1, 63);
    if (
      !Number.isInteger(rows) ||
      !Number.isInteger(columns) ||
      rows * columns > 4096 ||
      Object.keys(change).some(
        (key) => !["action", "rows", "columns"].includes(key),
      )
    )
      throw new Error("Invalid PPTX table cell dimensions");
    return;
  }
  if (change.action === "tableStructure") {
    if (
      !tableOperations.some((value) => value === change.operation) ||
      Object.keys(change).some((key) => key !== "action" && key !== "operation")
    )
      throw new Error("Invalid PPTX table structure edit");
    return;
  }
  if (change.action === "insertTable") {
    const rows = number(change.rows, 1, 1000),
      columns = number(change.columns, 1, 63);
    number(change.x, -14400, 14400);
    number(change.y, -14400, 14400);
    const width = number(change.width, 0.1, 14400);
    number(change.height, 0.1, 14400);
    if (
      !Number.isInteger(rows) ||
      !Number.isInteger(columns) ||
      rows * columns > 4096 ||
      Math.floor(Math.round(width * 12700) / columns) <= 182880 ||
      Object.keys(change).some(
        (key) =>
          !["action", "rows", "columns", "x", "y", "width", "height"].includes(
            key,
          ),
      )
    )
      throw new Error("Invalid PPTX table dimensions");
    return;
  }
  if (change.action === "imageInsets") {
    imageInsets(change.insets);
    if (
      Object.keys(change).length !== 2 ||
      Object.keys(change).some((key) => !["action", "insets"].includes(key))
    )
      throw new Error("Invalid image destination edit");
    return;
  }
  if (change.action === "lineEnd") {
    if (
      typeof change.side !== "string" ||
      !["head", "tail"].includes(change.side) ||
      Object.keys(change).some(
        (key) => !["action", "side", "end"].includes(key),
      )
    )
      throw new Error("Invalid PPTX line end edit");
    if (change.end !== null) checkPptxLineEnd(change.end);
    return;
  }
  if (change.action === "hyperlink") {
    if (Object.keys(change).some((key) => key !== "action" && key !== "link"))
      throw new Error("Invalid PPTX hyperlink edit");
    pptxHyperlink(change.link);
    return;
  }
  if (change.action === "shapeAdjustment") {
    if (!["adj", "adj1", "adj2"].includes(String(change.name)))
      throw new Error("Invalid PPTX shape adjustment");
    if (change.value !== null) number(change.value, 0, 21474.83647);
    return;
  }
  if (change.action === "strokeCap") {
    if (change.cap !== null && !pptxCaps.some((value) => value === change.cap))
      throw new Error("Invalid PPTX border cap");
    return;
  }
  if (change.action === "strokeJoin") {
    if (
      change.join !== null &&
      !pptxJoins.some((value) => value === change.join)
    )
      throw new Error("Invalid PPTX border join");
    if (change.join === "miter") number(change.miterLimit, 1, 1000);
    return;
  }
  if (change.action === "strokeDash") {
    if (
      change.dash !== null &&
      !pptxDashes.some((value) => value === change.dash)
    )
      throw new Error("Invalid PPTX border dash");
    return;
  }
  if (
    change.action === "imageOpacity" ||
    change.action === "fillOpacity" ||
    change.action === "strokeOpacity"
  ) {
    number(change.opacity, 0, 1);
    return;
  }
  if (change.action === "imageFillMode" || change.action === "imageMode") {
    if (
      (change.mode !== "stretch" && change.mode !== "tile") ||
      Object.keys(change).some((key) => !["action", "mode"].includes(key))
    )
      throw new Error("Invalid image fill mode");
    return;
  }
  if (
    change.action === "insertImage" ||
    change.action === "replaceImage" ||
    change.action === "imageFill"
  ) {
    if (
      !(change.bytes instanceof Uint8Array) ||
      !change.bytes.length ||
      change.bytes.length > 4194304
    )
      throw new Error("Invalid PPTX image input");
    if (change.action === "imageFill") {
      if (
        (change.mode !== "stretch" && change.mode !== "tile") ||
        !Array.isArray(change.objects) ||
        !change.objects.length ||
        change.objects.length > 256 ||
        change.objects.some(
          (id) => typeof id !== "string" || !id || id.length > 1024,
        ) ||
        new Set(change.objects).size !== change.objects.length ||
        Object.keys(change).some(
          (key) => !["action", "objects", "bytes", "mode"].includes(key),
        )
      )
        throw new Error("Invalid PPTX image fill targets");
      return;
    }
    if (change.action === "replaceImage") {
      if (
        typeof change.object !== "string" ||
        !change.object ||
        change.object.length > 1024
      )
        throw new Error("Invalid PPTX picture target");
      return;
    }
    number(change.x, -14400, 14400);
    number(change.y, -14400, 14400);
    number(change.width, 0.1, 14400);
    number(change.height, 0.1, 14400);
    return;
  }
  if (change.action === "imageCrop") {
    const l = number(change.left, 0, 0.99999),
      t = number(change.top, 0, 0.99999),
      r = number(change.right, 0, 0.99999),
      b = number(change.bottom, 0, 0.99999);
    if (
      Math.round(l * 100000) + Math.round(r * 100000) >= 100000 ||
      Math.round(t * 100000) + Math.round(b * 100000) >= 100000
    )
      throw new Error("Invalid PPTX picture crop area");
    return;
  }
  if (
    change.action === "clearTextFormat" ||
    change.action === "clearParagraphFormat"
  )
    return;
  if (change.action === "textParagraph") {
    checkPptxParagraphFormat(change.format);
    return;
  }
  if (change.action === "textFormat") {
    checkPptxTextFormat(change.format);
    return;
  }
  if (
    change.action === "textAlign" &&
    typeof change.alignment === "string" &&
    ["left", "center", "right", "justify"].includes(change.alignment)
  )
    return;
  if (change.action === "textInsets") {
    for (const key of ["left", "top", "right", "bottom"])
      number(change[key], 0, 14400);
    return;
  }
  if (
    change.action === "textAnchor" &&
    ["t", "ctr", "b"].includes(String(change.anchor))
  )
    return;
  if (change.action === "textWrap" && typeof change.wrap === "boolean") return;
  if (
    change.action === "textFit" &&
    typeof change.fit === "string" &&
    ["none", "shrink", "resize"].includes(String(change.fit))
  )
    return;
  if (change.action === "gradientFill") {
    if (
      Object.keys(change).some(
        (key) => !["action", "stops", "angle", "scaled"].includes(key),
      )
    )
      throw new Error("Invalid shape gradient fields");
    checkPptxBackgroundFill({
      kind: "linear",
      stops: change.stops,
      angle: change.angle,
      scaled: change.scaled,
    });
    return;
  }
  if (change.action === "fill" || change.action === "stroke") {
    if (
      change.color !== null &&
      (typeof change.color !== "string" || !/^[0-9a-f]{6}$/i.test(change.color))
    )
      throw new Error("Invalid shape color");
    if (change.action === "stroke") number(change.width, 0.1, 1000);
    return;
  }
  if (
    change.action === "delete" ||
    change.action === "group" ||
    change.action === "ungroup"
  )
    return;
  if (
    change.action === "align" &&
    ["left", "center", "right", "top", "middle", "bottom"].includes(
      String(change.alignment),
    ) &&
    ["slide", "selection", "active"].includes(String(change.relativeTo))
  )
    return;
  if (
    change.action === "distribute" &&
    ["horizontal", "vertical"].includes(String(change.axis)) &&
    ["slide", "selection"].includes(String(change.relativeTo))
  )
    return;
  if (change.action === "rotate") {
    number(change.angle, -360, 360);
    return;
  }
  if (
    change.action === "flip" &&
    ["horizontal", "vertical"].includes(String(change.axis))
  )
    return;
  if (
    change.action === "layer" &&
    ["front", "back", "forward", "backward"].includes(String(change.order))
  )
    return;
  if (change.action === "duplicate") {
    number(change.dx, -14400, 14400);
    number(change.dy, -14400, 14400);
    return;
  }
  if (
    change.action === "insertPlaceholder"
      ? typeof change.type !== "string" ||
        !pptxPlaceholderTypes.some((type) => type === change.type) ||
        Object.keys(change).some(
          (key) =>
            !["action", "type", "x", "y", "width", "height", "text"].includes(
              key,
            ),
        )
      : change.action !== "insert" ||
        !pptxInsertKinds.some((kind) => kind === change.kind)
  )
    throw new Error("Invalid PPTX object edit");
  number(change.x, -14400, 14400);
  number(change.y, -14400, 14400);
  const width = number(change.width, 0, 14400),
    height = number(change.height, 0, 14400);
  if (!(
    (width >= 0.1 && height >= 0.1) ||
    (change.kind === "line" && width + height >= 0.1)
  ))
    throw new Error("Invalid PPTX object size");
  const text = objectText(change.text);
  if (change.kind === "line" && text !== "")
    throw new Error("Invalid PPTX object text");
}

function objectText(text: unknown): string {
  if (
    typeof text !== "string" ||
    !text.isWellFormed() ||
    text.length > 32767 ||
    Array.from(text).some((character) => {
      const code = character.charCodeAt(0);
      return (
        (code < 32 && code !== 9 && code !== 10) ||
        code === 65534 ||
        code === 65535
      );
    }) ||
    text.split("\n").length > 256 ||
    text.split("\n").some((p) => p.length > 4096)
  )
    throw new Error("Invalid PPTX object text");
  return text;
}
