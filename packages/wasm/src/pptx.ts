import {
  checkPptxShow,
  pptxShowState,
  pptxShowLayout,
  type PptxShowCommand,
  type PptxShowState,
  type PptxShowLayout,
} from "./pptx-show.js";
export {
  checkPptxShow,
  type PptxShowAction,
  type PptxShowState,
  type PptxShowLayout,
} from "./pptx-show.js";
import {
  number,
  geometry,
  points,
  strings,
  checkPptxObjectEdit,
  checkPptxImageFill,
  imageInsets,
  type PptxObjectEdit,
  pptxHyperlink,
  type PptxHyperlink,
  pptxDashes,
  type PptxDash,
  pptxCaps,
  pptxJoins,
  type PptxCap,
  type PptxJoin,
  type PptxLineEnd,
  checkPptxLineEnd,
} from "./pptx-objects.js";
export {
  checkPptxObjectEdit,
  type PptxObjectEdit,
  type PptxHyperlink,
  type PptxDash,
  type PptxCap,
  type PptxJoin,
  type PptxLineEnd,
} from "./pptx-objects.js";
import {
  checkPptxSlideEdit,
  pptxPlaybackState,
  type PptxPlaybackState,
  checkPptxBackgroundFill,
  checkPptxBackground,
  pptxSections,
  pptxSlideLayouts,
  pptxComments,
  type PptxComments,
  type PptxSlideEdit,
  type PptxBackgroundFill,
  type PptxBackground,
  type PptxSections,
  type PptxSlideLayouts,
} from "./pptx-slides.js";
export {
  checkPptxSlideEdit,
  type PptxTransition,
  type PptxAdvance,
  type PptxAnimation,
  type PptxBackgroundFill,
  type PptxBackground,
  type PptxSlideEdit,
  type PptxSection,
  type PptxSections,
  type PptxSlideLayouts,
  pptxSlideLayouts,
  pptxComments,
  type PptxComments,
  type PptxComment,
  type PptxCommentAuthor,
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
import { presentationDateTime } from "./pptx-clock.js";
import { pptxFooter, type PptxFooter } from "./pptx-footer.js";
export type { PptxFooter, PptxFooterContent } from "./pptx-footer.js";
import {
  pptxThemeColors,
  pptxThemeFonts,
  type PptxThemeColor,
  type PptxThemeFont,
} from "./pptx-theme.js";
export type {
  PptxThemeColor,
  PptxThemeSlot,
  PptxThemeFont,
} from "./pptx-theme.js";
import { drawingBatch, type DrawMatrix, type DrawRect } from "./drawing.js";
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
import {
  pptxPrintLayout,
  type PptxOutputCommand,
  type PptxPrintLayout,
  type PptxLayout,
} from "./pptx-output.js";
export type { PptxPrintLayout, PptxLayout } from "./pptx-output.js";

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
export interface PptxQuery extends PptxPlaybackState {
  themeColors: PptxThemeColor[];
  themeFonts: PptxThemeFont[];
  revision: number;
  formatting: PptxFormatting;
  paragraph: PptxParagraphFormatting;
  textHyperlink: {
    value: PptxHyperlink | null;
    mixed: boolean;
    reason: string;
  };
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
  firstSlideNumber: number;
  sections: PptxSections;
  background: {
    value: PptxBackground;
    explicit: boolean;
    reason: string;
  };
  notes: { text: string; reason: string };
  footer: PptxFooter;
  comments: PptxComments;
  slideLayout: PptxSlideLayouts;
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
  | PptxShowCommand
  | PptxSearchCommand
  | PptxOutputCommand
  | { operation: "createPptx"; budget: Budget; dateTime?: string }
  | {
      operation: "openPptx";
      bytes: Uint8Array;
      budget: Budget;
      dateTime?: string;
    }
  | {
      operation: "dateTimePptx";
      revision: number;
      dateTime?: string;
      profile: Record<string, string>;
    }
  | { operation: "queryPptx" }
  | { operation: "followPptxHyperlink"; revision: number }
  | {
      operation: "editPptxSlides";
      revision: number;
      slide: string;
      change: PptxSlideEdit;
      profile: Record<string, string>;
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
  | {
      operation: "imagePptx";
      key: string;
      width: number;
      height: number;
      bytes: Uint8Array;
    };

type Result<C extends PptxCommand> = C["operation"] extends "controlShowPptx"
  ? PptxShowState
  : C["operation"] extends "layoutShowPptx"
    ? PptxShowLayout
    : C["operation"] extends "findPptx"
      ? PptxSearchResult
      : C["operation"] extends "printLayoutPptx"
        ? PptxPrintLayout
        : C["operation"] extends "layoutPptx"
          ? PptxLayout
          : C["operation"] extends "hitPptx"
            ? PptxHit
            : C["operation"] extends "selectionPptx"
              ? PptxGeometry
              : C["operation"] extends
                    "savePptx" | "imageBytesPptx" | "exportPptxPdf"
                ? Uint8Array
                : C["operation"] extends "imageKeysPptx" | "imageKeysShowPptx"
                  ? string[]
                  : C["operation"] extends "copyPptx"
                    ? { text: string }
                    : C["operation"] extends "imagePptx"
                      ? { key: string }
                      : PptxQuery;
export type PptxResult<C extends PptxCommand> = Result<C>;

export { isPptxCommand } from "./pptx-command.js";

function integer(value: unknown, high = 0x7fffffff): void {
  if (!Number.isInteger(number(value, 0, high)))
    throw new Error("Invalid PPTX integer");
}
export function pptxQuery(value: unknown): PptxQuery {
  const query = record(value);
  pptxPlaybackState(value);
  pptxThemeColors(query.themeColors);
  pptxThemeFonts(query.themeFonts);
  const notes = record(query.notes);
  pptxComments(query.comments);
  pptxSlideLayouts(query.slideLayout);
  pptxFooter(query.footer);
  integer(query.firstSlideNumber, 0xffffffff);
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
  checkPptxBackground(background.value);
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
  const slideIds = new Set(ids);
  const textHyperlink = record(query.textHyperlink),
    textLink = pptxHyperlink(textHyperlink.value);
  if (
    typeof textHyperlink.reason !== "string" ||
    typeof textHyperlink.mixed !== "boolean" ||
    (textHyperlink.mixed && textLink !== null) ||
    (textLink?.kind === "slide" && !slideIds.has(textLink.target))
  )
    throw new Error("Invalid text hyperlink");
  ids.clear();
  const parents = new Map<string, string>(),
    groups = new Set<string>();
  let units = 0;
  for (const item of query.objects) {
    const object = record(item);
    imageInsets(object.imageInsets);
    if (typeof object.imageInsetsReason !== "string")
      throw new Error("Invalid image destination reason");
    const hyperlink = record(object.hyperlink),
      link = pptxHyperlink(hyperlink.value);
    if (
      typeof hyperlink.reason !== "string" ||
      (link?.kind === "slide" && !slideIds.has(link.target))
    )
      throw new Error("Invalid object hyperlink");
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
        ["replaceReason", "cropReason", "opacityReason", "modeReason"],
        ["left", "top", "right", "bottom", "opacity"],
      ) ||
      (picture.mode !== "stretch" && picture.mode !== "tile")
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
    checkPptxImageFill(appearance, object.kind);
    if (appearance.gradient !== null) {
      checkPptxBackgroundFill(appearance.gradient);
      if (
        record(appearance.gradient).kind !== "linear" ||
        appearance.fill !== null ||
        appearance.fillOpacity !== 1
      )
        throw new Error("Invalid gradient appearance");
    }
    if (
      !hasFields(
        appearance,
        [
          "reason",
          "dashReason",
          "penReason",
          "lineEndReason",
          "fillOpacityReason",
          "imageFillReason",
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
    checkPptxLineEnd(appearance.headEnd);
    checkPptxLineEnd(appearance.tailEnd);
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
    case "controlShowPptx":
      pptxShowState(value);
      break;
    case "layoutShowPptx":
      pptxShowLayout(value);
      break;
    case "printLayoutPptx":
      pptxPrintLayout(value);
      break;
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
    case "imageKeysShowPptx":
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
    if (
      command.operation === "controlShowPptx" ||
      command.operation === "layoutShowPptx"
    )
      checkPptxShow(command);
    if (command.operation === "editPptxObjects")
      checkPptxObjectEdit(command.change);
    if (command.operation === "editPptxSlides")
      checkPptxSlideEdit(command.change);
    let value: unknown;
    if (
      (command.operation === "editPptxObjects" &&
        (command.change.action === "insertImage" ||
          command.change.action === "imageFill" ||
          command.change.action === "replaceImage")) ||
      (command.operation === "editPptxSlides" &&
        command.change.action === "backgroundImage")
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
      value = this.call({
        ...command,
        ...(command.operation === "openPptx"
          ? { dateTime: presentationDateTime(command.dateTime) }
          : {}),
        bytes: encodeBytes(command.bytes),
      });
    } else if (
      command.operation === "createPptx" ||
      command.operation === "dateTimePptx"
    )
      value = this.call({
        ...command,
        dateTime: presentationDateTime(command.dateTime),
      });
    else value = this.call(command);
    return pptxResult(command, value);
  }
}
