import type { PptxCommand } from "./pptx-command.js";
import {
  checkPptxImportInfo,
  checkPptxImportInput,
  type PptxImportInfo,
} from "./pptx-import.js";
export { checkPptxImportInput } from "./pptx-import.js";
export type { PptxImportInfo } from "./pptx-import.js";
import {
  checkPptxFragmentMedia,
  type PptxFragmentMedia,
} from "./pptx-media.js";
import {
  checkPptxTextFragment,
  checkPptxObjectFragment,
} from "./pptx-command.js";
export {
  checkPptxTextFragment,
  checkPptxObjectFragment,
} from "./pptx-command.js";
export type { PptxCommand } from "./pptx-command.js";
import {
  checkPptxShow,
  pptxShowState,
  pptxShowLayout,
  type PptxShowState,
  type PptxShowLayout,
} from "./pptx-show.js";
import { checkPptxConnectorQuery } from "./pptx-connectors.js";
import { checkPptxChart } from "./pptx-chart.js";
import { checkPptxMathItems } from "./pptx-math.js";
export type {
  MathFormat,
  PptxMathTarget,
  PptxMathValue,
  PptxMathItem,
  PptxMathEdit,
} from "./pptx-math.js";
export type { PptxChart } from "./pptx-chart.js";
export { pptxInsertKinds } from "./pptx-object-edit.js";
import {
  checkPptxMedia,
  checkMediaPlaybackQuery,
  type PptxMediaPlayback,
} from "./pptx-media.js";
export type {
  PptxMedia,
  PptxMediaPlayback,
  PptxFragmentMedia,
} from "./pptx-media.js";
export { mediaImageCommand } from "./pptx-show-media.js";
export type { PptxConnectorEnd, PptxConnector } from "./pptx-connectors.js";
import { checkPptxPlaceholderQuery } from "./pptx-placeholder.js";
export {
  pptxPlaceholderTypes,
  type PptxPlaceholder,
  type PptxPlaceholderType,
} from "./pptx-placeholder.js";
export {
  checkPptxShow,
  type PptxShowAction,
  type PptxShowState,
  type PptxShowLayout,
  type PptxShowInkChange,
  type PptxShowMediaChange,
  type PptxShowMediaState,
} from "./pptx-show.js";
import {
  number,
  geometry,
  strings,
  checkPptxObjectEdit,
  checkPptxGeometry,
  checkPptxImageFill,
  imageInsets,
  type PptxSelection,
  type PptxHit,
  type PptxGeometry,
  type PptxTable,
  checkPptxTable,
  pptxHyperlink,
  type PptxHyperlink,
  pptxDashes,
  pptxCaps,
  pptxJoins,
  checkPptxLineEnd,
} from "./pptx-objects.js";
export {
  checkPptxObjectEdit,
  type PptxObjectEdit,
  type PptxSelection,
  type PptxPoint,
  type PptxHit,
  type PptxGeometry,
  type PptxTable,
  type PptxHyperlink,
  type PptxTableStyle,
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
import { drawingBatch } from "./drawing.js";
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
  PptxParagraphTab,
  PptxParagraphFormatting,
} from "./pptx-format.js";
import {
  pptxPrintLayout,
  type PptxPrintLayout,
  type PptxLayout,
} from "./pptx-output.js";
export type { PptxPrintLayout, PptxLayout } from "./pptx-output.js";

import {
  checkPptxEditView,
  checkPptxGuides,
  checkPptxSnapping,
  type PptxEditView,
  type PptxGuides,
  type PptxSnapping,
} from "./pptx-view.js";
export type {
  PptxEditView,
  PptxMasterTextStyle,
  PptxMasterTextStyles,
  PptxMasterParagraphFormat,
  PptxMasterParagraphStyle,
  PptxGuide,
  PptxSpacing,
  PptxSizeMatch,
  PptxGuides,
  PptxSnapSettings,
  PptxSnapping,
} from "./pptx-view.js";
import type { PptxObject } from "./pptx-query.js";
export type { PptxObject } from "./pptx-query.js";
export interface PptxQuery extends PptxPlaybackState {
  mediaPlayback: {
    value: PptxMediaPlayback | null;
    reason: string;
  };
  editView: PptxEditView;
  guides: PptxGuides;
  snapping: PptxSnapping;
  table: PptxTable | null;
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
type Result<C extends PptxCommand> = C["operation"] extends "inspectPptxSlides"
  ? PptxImportInfo
  : C["operation"] extends "controlShowPptx" | "inkShowPptx" | "mediaShowPptx"
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
                      | "savePptx"
                      | "imageBytesPptx"
                      | "mediaBytesPptx"
                      | "exportPptxPdf"
                  ? Uint8Array
                  : C["operation"] extends "imageKeysPptx" | "imageKeysShowPptx"
                    ? string[]
                    : C["operation"] extends "copyPptx"
                      ? {
                          text: string;
                          fragment: string | null;
                          reason: string;
                        }
                      : C["operation"] extends "imagePptx"
                        ? { key: string }
                        : C["operation"] extends "objectFragmentImagesPptx"
                          ? string[]
                          : C["operation"] extends "objectFragmentMediaPptx"
                            ? PptxFragmentMedia[]
                            : PptxQuery;
export type PptxResult<C extends PptxCommand> = Result<C>;

export { isPptxCommand } from "./pptx-command.js";

function integer(value: unknown, high = 0x7fffffff): void {
  if (!Number.isInteger(number(value, 0, high)))
    throw new Error("Invalid PPTX integer");
}
export function pptxQuery(value: unknown): PptxQuery {
  const query = record(value);
  checkPptxGuides(query.guides);
  checkPptxSnapping(query.snapping);
  checkMediaPlaybackQuery(query.mediaPlayback);
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
  integer(query.historyBytes, 71303168);
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
  checkPptxEditView(query.editView, query.slide, ids);
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
    checkPptxPlaceholderQuery(object.placeholder);
    checkPptxConnectorQuery(object.connector, object.connectionSiteCount);
    checkPptxMedia(object.media);
    if (object.chart !== null) checkPptxChart(object.chart);
    checkPptxMathItems(object.equations);
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
      adjustments.values.length > 3
    )
      throw new Error("Invalid shape adjustments");
    const names = new Set<string>();
    for (const item of adjustments.values) {
      const guide = record(item);
      if (
        typeof guide.name !== "string" ||
        !["adj", "adj1", "adj2", "adj3"].includes(guide.name) ||
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
        ["anchor", "reason", "fit", "direction"],
        ["left", "top", "right", "bottom"],
      ) ||
      typeof frame.wrap !== "boolean" ||
      typeof frame.upright !== "boolean" ||
      typeof frame.rtlColumns !== "boolean" ||
      !["none", "shrink", "resize"].includes(String(frame.fit))
    )
      throw new Error("Invalid text frame");
    for (const key of ["left", "top", "right", "bottom"])
      number(frame[key], 0, 14400);
    number(frame.rotation, -2147483648 / 60000, 2147483647 / 60000);
    integer(frame.columns, 16);
    number(frame.columns, 1, 16);
    number(frame.columnGap, 0, 14400);
    const appearance = record(object.appearance);
    checkPptxImageFill(appearance, object.kind);
    if (appearance.gradient !== null) {
      checkPptxBackgroundFill(appearance.gradient);
      if (
        !["linear", "radial"].includes(
          String(record(appearance.gradient).kind),
        ) ||
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
          "parent",
          "name",
          "kind",
          "readOnlyReason",
          "textReadOnlyReason",
          "deleteReason",
          "duplicateReason",
          "rotateReason",
          "arrangeReason",
          "transformReason",
          "tableFillReason",
          "chartFillReason",
          "mediaFillReason",
          "chartDataReason",
          "shapeTypeReason",
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
  checkPptxTable(query.table, selected, selection.object);
  return value as PptxQuery;
}

/** Validate responses from both the Wasm ABI and Worker transport. */
export function pptxResult<C extends PptxCommand>(
  command: C,
  value: unknown,
): PptxResult<C> {
  switch (command.operation) {
    case "inspectPptxSlides":
      checkPptxImportInfo(value);
      break;
    case "inkShowPptx":
    case "mediaShowPptx":
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
    case "mediaBytesPptx":
    case "exportPptxPdf":
      if (
        !(value instanceof Uint8Array) ||
        value.length >
          (command.operation === "mediaBytesPptx" ? 16777216 : 67108864)
      )
        throw new Error("Invalid PPTX output bytes");
      break;
    case "imageKeysPptx":
    case "imageKeysShowPptx":
      strings(value, 256, 256);
      break;
    case "objectFragmentMediaPptx":
      checkPptxFragmentMedia(value);
      break;
    case "objectFragmentImagesPptx": {
      strings(value, 256, 2796204);
      if (
        !Array.isArray(value) ||
        value.some(
          (item) =>
            typeof item !== "string" || !/^[A-Za-z0-9+/]*={0,2}$/.test(item),
        ) ||
        value.reduce(
          (sum: number, item: unknown) =>
            sum + (typeof item === "string" ? item.length : 0),
          0,
        ) > 2796204
      )
        throw new Error("Invalid PPTX clipboard image resources");
      break;
    }
    case "copyPptx": {
      const object = record(value);
      if (
        Object.keys(object).length !== 3 ||
        typeof object.text !== "string" ||
        !object.text.isWellFormed() ||
        object.text.length > 32767 ||
        typeof object.reason !== "string" ||
        object.reason.length > 4096 ||
        (object.fragment !== null &&
          (typeof object.fragment !== "string" ||
            !object.fragment.isWellFormed() ||
            object.fragment.length > 100663296))
      )
        throw new Error("Invalid PPTX clipboard response");
      break;
    }
    case "imagePptx": {
      const object = record(value);
      if (typeof object.key !== "string" || object.key.length > 32767)
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
    case "selectionPptx":
      checkPptxGeometry(value);
      break;
    default:
      pptxQuery(value);
  }
  return value as PptxResult<C>;
}

/** One presentation per core session. Commands retain format-specific semantics. */
export class PptxSession extends WasmSession {
  execute<C extends PptxCommand>(command: C): PptxResult<C> {
    if (
      command.operation === "inspectPptxSlides" ||
      command.operation === "importPptxSlides"
    )
      checkPptxImportInput(
        command.bytes,
        command.indices,
        command.operation === "importPptxSlides",
      );
    if (
      command.operation === "controlShowPptx" ||
      command.operation === "inkShowPptx" ||
      command.operation === "mediaShowPptx" ||
      command.operation === "layoutShowPptx"
    )
      checkPptxShow(command);
    if (command.operation === "editPptxObjects")
      checkPptxObjectEdit(command.change);
    if (command.operation === "editPptxSlides")
      checkPptxSlideEdit(command.change);
    if (command.operation === "pastePptxFragment")
      checkPptxTextFragment(command.fragment);
    if (
      command.operation === "pastePptxObjects" ||
      command.operation === "objectFragmentImagesPptx" ||
      command.operation === "objectFragmentMediaPptx"
    )
      checkPptxObjectFragment(command.fragment);
    let value: unknown;
    if (
      command.operation === "editPptxObjects" &&
      (command.change.action === "insertMedia" ||
        command.change.action === "fillMedia")
    ) {
      value = this.call({
        ...command,
        change: {
          ...command.change,
          bytes: encodeBytes(command.change.bytes),
          poster: encodeBytes(command.change.poster),
        },
      });
    } else if (
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
      command.operation === "mediaBytesPptx" ||
      command.operation === "exportPptxPdf"
    )
      value = this.bytes(command);
    else if (
      command.operation === "openPptx" ||
      command.operation === "imagePptx" ||
      command.operation === "inspectPptxSlides" ||
      command.operation === "importPptxSlides"
    ) {
      if (
        command.bytes.length >
        (command.operation === "openPptx"
          ? Math.min(command.budget.fileBytes, command.budget.retainedBytes)
          : command.operation === "imagePptx"
            ? 16777216
            : 33554432)
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
