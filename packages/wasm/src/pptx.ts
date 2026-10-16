import { WasmSession, encodeBytes } from "./session.js";
import { record, hasFields } from "./validation.js";
import {
  drawingBatch,
  drawingMatrix,
  type DrawingBatch,
  type DrawMatrix,
  type DrawRect,
} from "./drawing.js";
import type { Budget } from "./foundation.js";

export interface PptxSelection {
  slide: string;
  object: string;
  objects: string[];
  mode: "object" | "text";
  anchor: number;
  focus: number;
}
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
  geometry:
    | (DrawRect & {
        matrix: DrawMatrix;
        rotation: number;
        flipX: boolean;
        flipY: boolean;
      })
    | null;
}
export interface PptxQuery {
  revision: number;
  groupReason: string;
  ungroupReason: string;
  width: number;
  height: number;
  slide: string;
  slides: { id: string; hidden: boolean; title: string }[];
  objects: PptxObject[];
  fontKeys: string[];
  imageKeys: string[];
  selection: PptxSelection;
  canUndo: boolean;
  canRedo: boolean;
  historyBytes: number;
  candidateId: number | null;
  readOnlyReason: string;
  slideOrderReason: string;
  slideVisibilityReason: string;
  background: { color: string; explicit: boolean; reason: string };
  diagnostics: string[];
}
export interface PptxLayout extends DrawingBatch {
  id: number;
  revision: number;
  slide: string;
  diagnostics: string[];
}
export interface PptxPoint {
  x: number;
  y: number;
}
export interface PptxGeometry {
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

export type PptxObjectEdit =
  | {
      action: "insert";
      kind:
        | "text"
        | "rect"
        | "roundRect"
        | "ellipse"
        | "line"
        | "leftArrow"
        | "rightArrow"
        | "upArrow"
        | "downArrow";
      x: number;
      y: number;
      width: number;
      height: number;
      text: string;
    }
  | { action: "delete" }
  | { action: "group" | "ungroup" }
  | { action: "duplicate"; dx: number; dy: number }
  | { action: "rotate"; angle: number }
  | { action: "flip"; axis: "horizontal" | "vertical" }
  | { action: "layer"; order: "front" | "back" | "forward" | "backward" }
  | {
      action: "align";
      alignment: "left" | "center" | "right" | "top" | "middle" | "bottom";
      relativeTo: "slide" | "selection" | "active";
    }
  | {
      action: "distribute";
      axis: "horizontal" | "vertical";
      relativeTo: "slide" | "selection";
    };

export type PptxCommand =
  | { operation: "createPptx"; budget: Budget }
  | { operation: "openPptx"; bytes: Uint8Array; budget: Budget }
  | { operation: "queryPptx" }
  | {
      operation: "editPptxSlides";
      revision: number;
      slide: string;
      change: PptxSlideEdit;
    }
  | {
      operation: "editPptxObjects";
      revision: number;
      change: PptxObjectEdit;
      profile: Record<string, string>;
    }
  | ({ operation: "selectPptx"; revision: number } & PptxSelection)
  | {
      operation: "replacePptx";
      revision: number;
      text: string;
      profile: Record<string, string>;
      candidateId?: number;
    }
  | {
      operation: "deletePptx";
      revision: number;
      backward: boolean;
      profile: Record<string, string>;
    }
  | {
      operation: "undoPptx" | "redoPptx" | "savePptx" | "copyPptx";
      revision: number;
    }
  | { operation: "layoutPptx"; profile: Record<string, string> }
  | {
      operation: "hitPptx";
      layoutId: number;
      x: number;
      y: number;
      tolerance: number;
    }
  | { operation: "selectionPptx"; layoutId: number }
  | {
      operation: "navigatePptx";
      revision: number;
      layoutId: number;
      direction:
        "next" | "previous" | "left" | "right" | "up" | "down" | "home" | "end";
      extend: boolean;
    }
  | { operation: "beginPptx"; revision: number; kind: "text" | "transform" }
  | ({
      operation: "transformPptx";
      revision: number;
      candidateId: number;
    } & DrawRect)
  | {
      operation: "dragPptx";
      revision: number;
      candidateId: number;
      dx: number;
      dy: number;
      handle: number;
    }
  | {
      operation: "finishPptx";
      revision: number;
      candidateId: number;
      profile: Record<string, string>;
    }
  | { operation: "cancelPptx"; revision: number; candidateId: number }
  | { operation: "imageBytesPptx"; key: string }
  | {
      operation: "imagePptx";
      key: string;
      width: number;
      height: number;
      bytes: Uint8Array;
    }
  | { operation: "imageKeysPptx"; all: boolean; hidden: boolean }
  | {
      operation: "exportPptxPdf";
      revision: number;
      all: boolean;
      hidden: boolean;
      profile: Record<string, string>;
      outputBytes: number;
    };

type Result<C extends PptxCommand> = C["operation"] extends "layoutPptx"
  ? PptxLayout
  : C["operation"] extends "hitPptx"
    ? PptxHit
    : C["operation"] extends "selectionPptx"
      ? PptxGeometry
      : C["operation"] extends "savePptx" | "imageBytesPptx" | "exportPptxPdf"
        ? Uint8Array
        : C["operation"] extends "imageKeysPptx"
          ? string[]
          : C["operation"] extends "copyPptx"
            ? { text: string }
            : C["operation"] extends "imagePptx"
              ? { key: string }
              : PptxQuery;
export type PptxResult<C extends PptxCommand> = Result<C>;

const names: ReadonlySet<string> = new Set([
  "openPptx",
  "createPptx",
  "queryPptx",
  "editPptxObjects",
  "editPptxSlides",
  "selectPptx",
  "replacePptx",
  "deletePptx",
  "undoPptx",
  "redoPptx",
  "savePptx",
  "copyPptx",
  "layoutPptx",
  "hitPptx",
  "selectionPptx",
  "navigatePptx",
  "beginPptx",
  "transformPptx",
  "dragPptx",
  "finishPptx",
  "cancelPptx",
  "imageBytesPptx",
  "imagePptx",
  "imageKeysPptx",
  "copyPptx",
  "exportPptxPdf",
]);
export function isPptxCommand(value: {
  operation: string;
}): value is PptxCommand {
  return names.has(value.operation);
}

export type PptxSlideEdit =
  | { action: "add" }
  | { action: "copy" }
  | { action: "delete" }
  | { action: "move"; index: number }
  | { action: "hidden"; hidden: boolean }
  | { action: "background"; value: string | null };

export function checkPptxSlideEdit(value: unknown): void {
  const change = record(value);
  if (change.action === "background") {
    if (
      change.value !== null &&
      (typeof change.value !== "string" || !/^[0-9a-f]{6}$/i.test(change.value))
    )
      throw new Error("Invalid slide background");
    return;
  }
  if (
    typeof change.action === "string" &&
    ["add", "copy", "delete"].includes(change.action)
  )
    return;
  if (
    change.action === "move" &&
    typeof change.index === "number" &&
    Number.isInteger(change.index) &&
    change.index >= 0 &&
    change.index < 256
  )
    return;
  if (change.action === "hidden" && typeof change.hidden === "boolean") return;
  throw new Error("Invalid slide edit");
}

function number(value: unknown, low = 0, high = 0x7fffffff): number {
  if (
    typeof value !== "number" ||
    !Number.isFinite(value) ||
    value < low ||
    value > high
  )
    throw new Error("Invalid PPTX number");
  return value;
}
function integer(value: unknown, high = 0x7fffffff): void {
  if (!Number.isInteger(number(value, 0, high)))
    throw new Error("Invalid PPTX integer");
}
export function checkPptxObjectEdit(value: unknown): void {
  const change = record(value);
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
    change.action !== "insert" ||
    ![
      "text",
      "rect",
      "roundRect",
      "ellipse",
      "line",
      "leftArrow",
      "rightArrow",
      "upArrow",
      "downArrow",
    ].includes(String(change.kind))
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
  const text = change.text;
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
    text.split("\n").some((p) => p.length > 4096) ||
    (change.kind === "line" && text !== "")
  )
    throw new Error("Invalid PPTX object text");
}
function strings(value: unknown, count: number, units: number): void {
  if (
    !Array.isArray(value) ||
    value.length > count ||
    value.some((item) => typeof item !== "string" || item.length > units)
  )
    throw new Error("Invalid PPTX string array");
}
function geometry(value: unknown): void {
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
function points(value: unknown, max = 4): void {
  if (!Array.isArray(value) || value.length > max)
    throw new Error("Invalid PPTX polygon");
  for (const point of value) {
    const p = record(point);
    number(p.x, -1e9, 1e9);
    number(p.y, -1e9, 1e9);
  }
}
export function pptxQuery(value: unknown): PptxQuery {
  const query = record(value);
  const background = record(query.background);
  if (
    typeof background.color !== "string" ||
    !/^[0-9a-f]{6}$/i.test(background.color) ||
    typeof background.explicit !== "boolean" ||
    typeof background.reason !== "string"
  )
    throw new Error("Invalid slide background query");
  if (
    !hasFields(
      query,
      [
        "slide",
        "readOnlyReason",
        "slideOrderReason",
        "slideVisibilityReason",
        "groupReason",
        "ungroupReason",
      ],
      ["revision", "width", "height", "historyBytes"],
    ) ||
    typeof query.canUndo !== "boolean" ||
    typeof query.canRedo !== "boolean" ||
    !Array.isArray(query.slides) ||
    query.slides.length === 0 ||
    query.slides.length > 256 ||
    !Array.isArray(query.objects) ||
    query.objects.length > 4096
  )
    throw new Error("Invalid PPTX query");
  integer(query.revision);
  integer(query.historyBytes, 4194304);
  number(query.width, 1, 14400);
  number(query.height, 1, 14400);
  if (query.candidateId !== null) integer(query.candidateId);
  const ids = new Set<string>();
  for (const item of query.slides) {
    const slide = record(item);
    if (
      !hasFields(slide, ["id", "title"], []) ||
      typeof slide.id !== "string" ||
      ids.has(slide.id) ||
      typeof slide.hidden !== "boolean"
    )
      throw new Error("Invalid PPTX slide");
    ids.add(slide.id);
  }
  if (typeof query.slide !== "string" || !ids.has(query.slide))
    throw new Error("Invalid current slide");
  ids.clear();
  const parents = new Map<string, string>(),
    groups = new Set<string>();
  let units = 0;
  for (const item of query.objects) {
    const object = record(item);
    if (
      !hasFields(
        object,
        [
          "id",
          "parent",
          "name",
          "kind",
          "text",
          "readOnlyReason",
          "textReadOnlyReason",
          "deleteReason",
          "duplicateReason",
          "rotateReason",
          "arrangeReason",
        ],
        [],
      ) ||
      typeof object.id !== "string" ||
      ids.has(object.id) ||
      typeof object.text !== "string" ||
      object.text.length > 32767
    )
      throw new Error("Invalid PPTX object");
    ids.add(object.id);
    parents.set(object.id, String(object.parent));
    if (object.kind === "group") groups.add(object.id);
    units += object.text.length;
    if (object.geometry !== null) geometry(object.geometry);
  }
  if (units > 1048576) throw new Error("PPTX query text exceeds budget");
  for (const id of ids) {
    let parent = parents.get(id) ?? "";
    for (let depth = 0; parent; depth++) {
      if (depth >= 16 || !groups.has(parent))
        throw new Error("Invalid PPTX group hierarchy");
      parent = parents.get(parent) ?? "";
    }
  }
  const selection = record(query.selection);
  if (
    !hasFields(selection, ["slide", "object", "mode"], ["anchor", "focus"]) ||
    selection.slide !== query.slide ||
    (selection.object !== "" &&
      (typeof selection.object !== "string" || !ids.has(selection.object))) ||
    !["object", "text"].includes(String(selection.mode))
  )
    throw new Error("Invalid PPTX selection");
  integer(selection.anchor, 32767);
  integer(selection.focus, 32767);
  strings(selection.objects, 256, 1024);
  const selected = selection.objects as string[];
  if (
    new Set(selected).size !== selected.length ||
    selected.some((id) => !ids.has(id)) ||
    (selected.length === 0
      ? selection.object !== ""
      : !selected.includes(String(selection.object))) ||
    (selection.mode === "text" && selected.length !== 1)
  )
    throw new Error("Invalid PPTX object selection");
  strings(query.fontKeys, 256, 256);
  strings(query.imageKeys, 256, 256);
  strings(query.diagnostics, 8192, 4096);
  return value as PptxQuery;
}

/** Validate responses from both the Wasm ABI and Worker transport. */
export function pptxResult<C extends PptxCommand>(
  command: C,
  value: unknown,
): PptxResult<C> {
  switch (command.operation) {
    case "savePptx":
    case "imageBytesPptx":
    case "exportPptxPdf":
      if (!(value instanceof Uint8Array) || value.length > 67108864)
        throw new Error("Invalid PPTX output bytes");
      break;
    case "imageKeysPptx":
      strings(value, 256, 256);
      break;
    case "copyPptx":
    case "imagePptx": {
      const object = record(value);
      const field = command.operation === "copyPptx" ? "text" : "key";
      if (typeof object[field] !== "string" || object[field].length > 32767)
        throw new Error("Invalid PPTX text response");
      break;
    }
    case "layoutPptx": {
      drawingBatch(value);
      const layout = record(value);
      integer(layout.id);
      integer(layout.revision);
      if (
        typeof layout.slide !== "string" ||
        !Array.isArray(layout.regions) ||
        layout.regions.length !== 1
      )
        throw new Error("Invalid slide layout");
      strings(layout.diagnostics, 8192, 4096);
      break;
    }
    case "hitPptx": {
      const hit = record(value);
      if (
        !hasFields(
          hit,
          ["object", "readOnlyReason", "textReadOnlyReason"],
          ["offset"],
        )
      )
        throw new Error("Invalid PPTX hit");
      integer(hit.offset, 32767);
      break;
    }
    case "selectionPptx": {
      const selection = record(value);
      integer(selection.layoutId);
      integer(selection.revision);
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
        for (const key of ["x", "y", "endX", "endY"])
          number(caret[key], -1e9, 1e9);
        number(caret.height, 0, 14400);
      }
      break;
    }
    default:
      pptxQuery(value);
  }
  return value as PptxResult<C>;
}

/** One presentation per core session. Commands retain format-specific semantics. */
export class PptxSession extends WasmSession {
  execute<C extends PptxCommand>(command: C): PptxResult<C> {
    if (command.operation === "editPptxObjects")
      checkPptxObjectEdit(command.change);
    if (command.operation === "editPptxSlides")
      checkPptxSlideEdit(command.change);
    let value: unknown;
    if (
      command.operation === "savePptx" ||
      command.operation === "imageBytesPptx" ||
      command.operation === "exportPptxPdf"
    )
      value = this.bytes(command);
    else if (
      command.operation === "openPptx" ||
      command.operation === "imagePptx"
    ) {
      if (
        command.bytes.length >
        (command.operation === "openPptx"
          ? Math.min(command.budget.fileBytes, command.budget.retainedBytes)
          : 16777216)
      )
        throw new Error("PPTX input exceeds budget");
      value = this.call({ ...command, bytes: encodeBytes(command.bytes) });
    } else value = this.call(command);
    return pptxResult(command, value);
  }
}
