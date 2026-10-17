import {
  number,
  checkPptxObjectEdit,
  type PptxObjectEdit,
  pptxDashes,
  type PptxDash,
  pptxCaps,
  pptxJoins,
  type PptxCap,
  type PptxJoin,
} from "./pptx-objects.js";
export {
  checkPptxObjectEdit,
  type PptxObjectEdit,
  type PptxDash,
  type PptxCap,
  type PptxJoin,
} from "./pptx-objects.js";
import {
  checkPptxSlideEdit,
  pptxSections,
  pptxSlideLayouts,
  type PptxSlideEdit,
  type PptxBackgroundFill,
  type PptxSections,
  type PptxSlideLayouts,
} from "./pptx-slides.js";
export {
  checkPptxSlideEdit,
  type PptxBackgroundFill,
  type PptxSlideEdit,
  type PptxSection,
  type PptxSections,
  type PptxSlideLayouts,
  pptxSlideLayouts,
} from "./pptx-slides.js";
import { WasmSession, encodeBytes } from "./session.js";
import {
  preparePptxSearch,
  pptxSearchResult,
  type PptxSearchCommand,
  type PptxSearchResult,
} from "./pptx-search.js";
export type { PptxFindOptions, PptxSearchResult } from "./pptx-search.js";
export { preparePptxSearch, pptxFindOptions } from "./pptx-search.js";
import { record, hasFields } from "./validation.js";
import {
  drawingBatch,
  drawingMatrix,
  type DrawingBatch,
  type DrawMatrix,
  type DrawRect,
} from "./drawing.js";
import type { Budget } from "./foundation.js";
import {
  checkPptxFormatting,
  checkPptxParagraphFormatting,
  type PptxFormatting,
  type PptxParagraphFormatting,
} from "./pptx-format.js";
export type {
  PptxTextFormat,
  PptxFormatting,
  PptxTextSpacing,
  PptxListFormat,
  PptxParagraphFormat,
  PptxParagraphFormatting,
} from "./pptx-format.js";

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
  shapeAdjustments: {
    preset: string;
    reason: string;
    values: { name: "adj" | "adj1" | "adj2"; value: number; maximum: number }[];
  };
  picture: {
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
    fillOpacity: number;
    strokeOpacity: number;
    fillOpacityReason: string;
    strokeOpacityReason: string;
    cap: PptxCap;
    join: PptxJoin;
    miterLimit: number;
    penReason: string;
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
export interface PptxQuery {
  revision: number;
  formatting: PptxFormatting;
  paragraph: PptxParagraphFormatting;
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
  slideSizeReason: string;
  slideVisibilityReason: string;
  sections: PptxSections;
  background: {
    value: PptxBackgroundFill;
    explicit: boolean;
    reason: string;
  };
  notes: { text: string; reason: string };
  slideLayout: PptxSlideLayouts;
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

export type PptxCommand =
  | PptxSearchCommand
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

type Result<C extends PptxCommand> = C["operation"] extends "findPptx"
  ? PptxSearchResult
  : C["operation"] extends "layoutPptx"
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
  "findPptx",
  "replacePptxMatches",
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

function integer(value: unknown, high = 0x7fffffff): void {
  if (!Number.isInteger(number(value, 0, high)))
    throw new Error("Invalid PPTX integer");
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
  const notes = record(query.notes);
  pptxSlideLayouts(query.slideLayout);
  checkPptxSlideEdit({ action: "notes", text: notes.text });
  if (typeof notes.reason !== "string") throw new Error("Invalid notes query");
  checkPptxFormatting(query.formatting);
  checkPptxParagraphFormatting(query.paragraph);
  const background = record(query.background);
  if (
    typeof background.explicit !== "boolean" ||
    typeof background.reason !== "string"
  )
    throw new Error("Invalid slide background query");
  checkPptxSlideEdit({ action: "background", value: background.value });
  if (
    !hasFields(
      query,
      [
        "slide",
        "readOnlyReason",
        "slideOrderReason",
        "slideSizeReason",
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
  pptxSections(query.sections, [...ids]);
  ids.clear();
  const parents = new Map<string, string>(),
    groups = new Set<string>();
  let units = 0;
  for (const item of query.objects) {
    const object = record(item);
    const adjustments = record(object.shapeAdjustments);
    if (
      !hasFields(adjustments, ["preset", "reason"], []) ||
      !Array.isArray(adjustments.values) ||
      adjustments.values.length > 2
    )
      throw new Error("Invalid shape adjustments");
    const names = new Set<string>();
    for (const item of adjustments.values) {
      const guide = record(item);
      if (
        typeof guide.name !== "string" ||
        !["adj", "adj1", "adj2"].includes(guide.name) ||
        names.has(guide.name)
      )
        throw new Error("Invalid shape adjustment guide");
      names.add(guide.name);
      const maximum = number(guide.maximum, 0, 21474.83647);
      number(guide.value, 0, maximum);
    }
    const picture = record(object.picture);
    if (
      !hasFields(
        picture,
        ["replaceReason", "cropReason", "opacityReason"],
        ["left", "top", "right", "bottom", "opacity"],
      )
    )
      throw new Error("Invalid picture query");
    number(picture.opacity, 0, 1);
    for (const key of ["left", "top", "right", "bottom"])
      number(picture[key], 0, 0.99999);
    if (
      Number(picture.left) + Number(picture.right) >= 1 ||
      Number(picture.top) + Number(picture.bottom) >= 1
    )
      throw new Error("Invalid picture crop area");
    const frame = record(object.textFrame);
    if (
      !hasFields(
        frame,
        ["anchor", "reason", "fit"],
        ["left", "top", "right", "bottom"],
      ) ||
      typeof frame.wrap !== "boolean" ||
      !["none", "shrink", "resize"].includes(String(frame.fit))
    )
      throw new Error("Invalid text frame");
    for (const key of ["left", "top", "right", "bottom"])
      number(frame[key], 0, 14400);
    const appearance = record(object.appearance);
    if (
      !hasFields(
        appearance,
        [
          "reason",
          "dashReason",
          "penReason",
          "fillOpacityReason",
          "strokeOpacityReason",
        ],
        ["width", "miterLimit", "fillOpacity", "strokeOpacity"],
      ) ||
      !pptxCaps.some((value) => value === appearance.cap) ||
      !pptxJoins.some((value) => value === appearance.join) ||
      !pptxDashes.some((value) => value === appearance.dash) ||
      ![appearance.fill, appearance.stroke].every(
        (color) =>
          color === null ||
          (typeof color === "string" && /^[0-9a-f]{6}$/i.test(color)),
      )
    )
      throw new Error("Invalid shape appearance");
    number(appearance.width, 1 / 12700, 1000);
    number(appearance.miterLimit, 1, 1000);
    number(appearance.fillOpacity, 0, 1);
    number(appearance.strokeOpacity, 0, 1);
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
    case "findPptx":
      pptxSearchResult(value);
      break;
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
      command.operation === "editPptxObjects" &&
      (command.change.action === "insertImage" ||
        command.change.action === "replaceImage")
    ) {
      value = this.call({
        ...command,
        change: { ...command.change, bytes: encodeBytes(command.change.bytes) },
      });
    } else if (
      command.operation === "findPptx" ||
      command.operation === "replacePptxMatches"
    )
      value = this.call(preparePptxSearch(command));
    else if (
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
