import {
  docxCharts,
  checkDocxChartEdit,
  type DocxChartEdit,
} from "./docx-chart.js";
export * from "./docx-chart.js";
export { type ChartSettings } from "./chart.js";
import { FoundationInkSession } from "./docx-ink.js";
export * from "./docx-ink.js";
export * from "./docx-tracking.js";
export * from "./docx-clipboard.js";
export * from "./docx-toc.js";
export * from "./docx-index.js";
export * from "./docx-sources.js";
export * from "./docx-protection.js";
export {
  checkRunningArea,
  checkRunningKind,
  checkRunningVariant,
  checkRunningOptions,
  checkDocxCoverPage,
  checkDocxCaption,
  type DocxCaption,
  type DocxCoverPage,
  type DocxSectionBreak,
  checkSectionBreak,
  docxRunningArea,
  type DocxRunningArea,
  type DocxRunningContent,
  type DocxPageField,
  type DocxBodyField,
  checkBodyField,
  checkPageField,
  type DocxBodyPageField,
  docxBodyPageField,
  type DocxRunningKind,
  type DocxRunningVariant,
} from "./docx-page.js";
export * from "./docx-watermark.js";
import {
  checkFormatPatch,
  checkDocxHyperlink,
  editState,
  createdDocxStyle,
  type EditState,
  type CreatedDocxStyle,
  docxStyleCatalog,
  type DocxStyleCatalog,
  docxFormatting,
  copiedFormat,
  checkStyleUpdate,
  type CopiedFormat,
  type DocxStyleUpdate,
  type DocxStyleCreation,
  checkStyleCreation,
  checkDefaultTabStop,
  type DocxFormatting,
  type CharacterFormatPatch,
  type ParagraphFormatPatch,
} from "./docx-format.js";
export {
  checkDocxComment,
  docxComments,
  docxCommentNavigation,
  type DocxCommentNavigation,
  type DocxCommentEdit,
  type DocxComments,
} from "./docx-comments.js";
export * from "./docx-format.js";
export * from "./docx-ruler.js";
export * from "./docx-picture.js";
export * from "./docx-shape.js";
export * from "./docx-math.js";
import {
  docxShapes,
  checkDocxShapeEdit,
  type DocxShapeEdit,
} from "./docx-shape.js";
export * from "./docx-overview.js";
export {
  docxRevisions,
  docxRevisionGeometry,
  checkDocxRevisionEdit,
  type DocxRevisions,
  type DocxRevisionEdit,
} from "./docx-revisions.js";

import {
  prepareDocxPictureEdit,
  docxPictures,
  type DocxPictureEdit,
  checkDocxDrawingGesture,
  type DocxDrawingGestureCommand,
} from "./docx-picture.js";
export * from "./docx-list.js";
export * from "./docx-list-level.js";
import {
  checkListLevelUpdate,
  type DocxListLevelUpdate,
} from "./docx-list-level.js";
import {
  checkListEdit,
  docxListCatalog,
  type DocxListEdit,
  type DocxListCatalog,
} from "./docx-list.js";
import { DocumentError, encodeBytes } from "./session.js";
export { DocumentError, resourceBudget } from "./session.js";
import {
  checkDocxTableSize,
  checkDocxTableEdit,
  type DocxTableEdit,
} from "./docx-table.js";
export * from "./docx-table.js";
import {
  docxThemeColors,
  checkDocxThemeColor,
  type DocxThemeSlot,
  docxThemeFonts,
  checkDocxThemeFonts,
  type DocxThemeFontEdit,
} from "./docx-theme.js";
export * from "./docx-theme.js";
/** Logical soft line break; DOCX serializes it as w:br, while LF creates a paragraph. */
export const DOCX_SOFT_BREAK = "\u2028";
/** Logical page break; serialized as w:br w:type="page", never as an XML control character. */
export const DOCX_PAGE_BREAK = "\u000c";
/** Logical column break; serialized as w:br w:type="column". */
export const DOCX_COLUMN_BREAK = "\u000b";
import {
  docxFlow,
  pageLayout,
  type DocxFlow,
  type PageLayout,
} from "./preview.js";
import { record, hasFields, arrayOf, glyphs } from "./validation.js";
import {
  checkFindOptions,
  docxSearchResult,
  type DocxFindOptions,
  type DocxSearchResult,
} from "./docx-search.js";
export {
  checkFindOptions,
  docxSearchResult,
  type DocxFindOptions,
  type DocxSearchResult,
} from "./docx-search.js";

import type { Budget } from "./validation.js";
export type { Budget } from "./validation.js";

export type { DocxPosition, DocxSelection } from "./docx-hit.js";
import type { DocxPosition, DocxSelection } from "./docx-hit.js";

import { docxHit, type DocxHit } from "./docx-hit.js";
export { docxHit, type DocxHit } from "./docx-hit.js";

export {
  docxSelectionGeometry,
  type DocxSelectionGeometry,
} from "./docx-hit.js";
import {
  docxSelectionGeometry,
  type DocxSelectionGeometry,
} from "./docx-hit.js";

export type NavigationDirection =
  "left" | "right" | "up" | "down" | "home" | "end";

export interface DocxNavigation {
  state: EditState;
  caret: DocxHit;
}

export function docxNavigation(value: unknown): DocxNavigation {
  const object = record(value);
  return { state: editState(object.state), caret: docxHit(object.caret) };
}

export interface DocxQuery {
  revision: number;
  compositionId: number | null;
  mainPart: string;
  texts: { id: number; paragraph: number; run: number; text: string }[];
  relationships: {
    owner: string;
    id: string;
    type: string;
    target: string;
    external: boolean;
  }[];
  diagnostics: string[];
  decodedBytes: number;
}

export interface ShapeBatch {
  text: string;
  carets: { offset: number; before: number; after: number }[];
  glyphs: {
    id: number;
    cluster: number;
    font: number;
    outline: string;
    x: number;
    y: number;
    scale: number;
    advance: number;
    yAdvance: number;
    xOffset: number;
    yOffset: number;
  }[];
  outlines: { key: string; path: string }[];
  runs: {
    start: number;
    end: number;
    level: number;
    font: number;
    script: string;
    language: string;
  }[];
  fonts: {
    identity: string;
    sha256: string;
    face: number;
    variation: string;
    upem: number;
    ascent: number;
    descent: number;
    bbox: number[];
    capHeight: number;
    italicAngle: number;
  }[];
  diagnostics: { code: string; cluster: number; codepoint: number }[];
  width: number;
  fontBytes: number;
  outlineBytes: number;
}

export function docxQuery(value: unknown): DocxQuery {
  const object = record(value);
  if (
    !hasFields(value, ["mainPart"], ["revision", "decodedBytes"]) ||
    (object.compositionId !== null &&
      (typeof object.compositionId !== "number" ||
        !Number.isSafeInteger(object.compositionId) ||
        object.compositionId <= 0)) ||
    !arrayOf(object.texts, (entry) =>
      hasFields(entry, ["text"], ["id", "paragraph", "run"]),
    ) ||
    !arrayOf(
      object.relationships,
      (entry) =>
        hasFields(entry, ["owner", "id", "type", "target"], []) &&
        typeof record(entry).external === "boolean",
    ) ||
    !arrayOf(object.diagnostics, (entry) => typeof entry === "string")
  )
    throw new Error("Invalid DOCX query returned by Wasm");
  return value as DocxQuery;
}

export function shapeBatch(value: unknown): ShapeBatch {
  const object = record(value);
  if (
    !hasFields(value, ["text"], ["width", "fontBytes", "outlineBytes"]) ||
    !glyphs(object.glyphs) ||
    !arrayOf(
      object.carets,
      (entry) =>
        hasFields(entry, [], ["offset", "before", "after"]) &&
        Number.isSafeInteger(record(entry).offset) &&
        Number(record(entry).offset) >= 0,
    ) ||
    !arrayOf(object.outlines, (entry) =>
      hasFields(entry, ["key", "path"], []),
    ) ||
    !arrayOf(object.runs, (entry) =>
      hasFields(
        entry,
        ["script", "language"],
        ["start", "end", "level", "font"],
      ),
    ) ||
    !arrayOf(
      object.fonts,
      (entry) =>
        hasFields(
          entry,
          ["identity", "variation", "sha256"],
          ["face", "upem", "ascent", "descent", "capHeight", "italicAngle"],
        ) &&
        arrayOf(
          record(entry).bbox,
          (value) => typeof value === "number" && Number.isFinite(value),
        ),
    ) ||
    !arrayOf(object.diagnostics, (entry) =>
      hasFields(entry, ["code"], ["cluster", "codepoint"]),
    )
  )
    throw new Error("Invalid shape batch returned by Wasm");
  return value as ShapeBatch;
}

export class FoundationSession extends FoundationInkSession {
  charts(revision: number) {
    return docxCharts(this.call({ operation: "docxCharts", revision }));
  }
  editChart(
    revision: number,
    chart: DocxChartEdit,
    profile: Record<string, string> = {},
  ): EditState {
    checkDocxChartEdit(chart);
    return editState(
      this.call({ operation: "editDocxChart", revision, chart, profile }),
    );
  }
  shape(text: string, size = 32, language = "und"): ShapeBatch {
    return shapeBatch(this.call({ operation: "shape", text, size, language }));
  }

  openDocx(bytes: Uint8Array, budget: Budget): DocxQuery {
    if (bytes.length > budget.fileBytes || bytes.length > budget.retainedBytes)
      throw new DocumentError(
        "limit-exceeded",
        "Byte input exceeds budget",
        "",
        -1,
      );
    return docxQuery(
      this.call({ operation: "openDocx", bytes: encodeBytes(bytes), budget }),
    );
  }

  query(): DocxQuery {
    return docxQuery(this.call({ operation: "query" }));
  }
  createDocx(budget: Budget): DocxQuery {
    return docxQuery(this.call({ operation: "createDocx", budget }));
  }
  queryFormatting(revision: number, selection: DocxSelection): DocxFormatting {
    return docxFormatting(
      this.call({ operation: "queryFormatting", revision, selection }),
    );
  }
  styles(revision: number, kind: "paragraph" | "character"): DocxStyleCatalog {
    return docxStyleCatalog(
      this.call({ operation: "styleCatalog", revision, kind }),
    );
  }
  themeColors(revision: number) {
    return docxThemeColors(
      this.call({ operation: "docxThemeColors", revision }),
    );
  }
  themeFonts(revision: number) {
    return docxThemeFonts(this.call({ operation: "docxThemeFonts", revision }));
  }
  setThemeFonts(
    revision: number,
    fonts: DocxThemeFontEdit[],
    profile: Record<string, string>,
  ): EditState {
    checkDocxThemeFonts(fonts);
    return editState(
      this.call({ operation: "setDocxThemeFonts", revision, fonts, profile }),
    );
  }
  setThemeColor(
    revision: number,
    slot: DocxThemeSlot,
    color: string,
  ): EditState {
    checkDocxThemeColor(slot, color);
    return editState(
      this.call({ operation: "setDocxThemeColor", revision, slot, color }),
    );
  }
  lists(revision: number): DocxListCatalog {
    return docxListCatalog(this.call({ operation: "listCatalog", revision }));
  }
  editList(
    revision: number,
    selection: DocxSelection,
    change: DocxListEdit,
  ): EditState {
    checkListEdit(change);
    return editState(
      this.call({ operation: "editList", revision, selection, change }),
    );
  }
  updateListLevel(
    revision: number,
    id: number,
    level: number,
    definition: DocxListLevelUpdate,
  ): EditState {
    checkListLevelUpdate(id, level, definition);
    return editState(
      this.call({
        operation: "updateListLevel",
        revision,
        listId: id,
        level,
        definition,
      }),
    );
  }
  createStyle(revision: number, style: DocxStyleCreation): CreatedDocxStyle {
    checkStyleCreation(style);
    return createdDocxStyle(
      this.call({ operation: "createStyle", revision, ...style }),
    );
  }
  deleteStyle(revision: number, key: string, replacement: string): EditState {
    return editState(
      this.call({ operation: "deleteStyle", revision, key, replacement }),
    );
  }
  updateStyle(
    revision: number,
    key: string,
    format: DocxStyleUpdate,
  ): EditState {
    checkStyleUpdate(format);
    return editState(
      this.call({ operation: "updateStyle", revision, key, format }),
    );
  }
  captureFormat(revision: number, selection: DocxSelection): CopiedFormat {
    return copiedFormat(
      this.call({ operation: "captureFormat", revision, selection }),
    );
  }
  applyFormat(
    revision: number,
    selection: DocxSelection,
    format: CopiedFormat,
    profile: Record<string, string> = {},
  ): EditState {
    copiedFormat(format);
    return editState(
      this.call({
        operation: "applyFormat",
        revision,
        selection,
        format,
        profile,
      }),
    );
  }
  setCharacterFormat(
    revision: number,
    selection: DocxSelection,
    format: CharacterFormatPatch,
    profile: Record<string, string> = {},
  ): EditState {
    checkFormatPatch(format);
    return editState(
      this.call({
        operation: "setCharacterFormat",
        revision,
        selection,
        format,
        profile,
      }),
    );
  }
  setHyperlink(
    revision: number,
    selection: DocxSelection,
    target: string | null,
    text?: string,
  ): EditState {
    checkDocxHyperlink(target, text);
    return editState(
      this.call({
        operation: "setHyperlink",
        revision,
        selection,
        target,
        ...(text === undefined ? {} : { text }),
      }),
    );
  }
  setParagraphFormat(
    revision: number,
    selection: DocxSelection,
    format: ParagraphFormatPatch,
    profile: Record<string, string> = {},
  ): EditState {
    checkFormatPatch(format, true);
    return editState(
      this.call({
        operation: "setParagraphFormat",
        revision,
        selection,
        format,
        profile,
      }),
    );
  }

  editState(): EditState {
    return editState(this.call({ operation: "editState" }));
  }
  pictures(revision: number) {
    return docxPictures(this.call({ operation: "docxPictures", revision }));
  }
  shapes(revision: number) {
    return docxShapes(this.call({ operation: "docxShapes", revision }));
  }
  editShape(
    revision: number,
    shape: DocxShapeEdit,
    profile: Record<string, string> = {},
  ): EditState {
    checkDocxShapeEdit(shape);
    return editState(
      this.call({ operation: "editDocxShape", revision, shape, profile }),
    );
  }
  drawingGesture(
    revision: number,
    change: DocxDrawingGestureCommand,
    profile: Record<string, string> = {},
  ) {
    checkDocxDrawingGesture(change);
    return editState(
      this.call({ operation: "docxDrawingGesture", revision, change, profile }),
    );
  }
  editPicture(
    revision: number,
    picture: DocxPictureEdit,
    profile: Record<string, string> = {},
  ): EditState {
    return editState(
      this.call({
        operation: "editDocxPicture",
        revision,
        picture: prepareDocxPictureEdit(picture),
        profile,
      }),
    );
  }
  insertTable(
    revision: number,
    selection: DocxSelection,
    rows: number,
    columns: number,
    profile: Record<string, string>,
  ): EditState {
    checkDocxTableSize(rows, columns);
    return editState(
      this.call({
        operation: "insertDocxTable",
        revision,
        selection,
        rows,
        columns,
        profile,
      }),
    );
  }
  setDefaultTabStop(revision: number, interval: number | null): EditState {
    checkDefaultTabStop(interval);
    return editState(
      this.call({ operation: "setDefaultTabStop", revision, interval }),
    );
  }
  editTable(
    revision: number,
    selection: DocxSelection,
    change: DocxTableEdit,
    profile: Record<string, string> = {},
  ): EditState {
    checkDocxTableEdit(change);
    return editState(
      this.call({
        operation: "editDocxTable",
        revision,
        selection,
        change,
        profile,
      }),
    );
  }
  tabDocx(revision: number, backward = false): EditState {
    return editState(this.call({ operation: "tabDocx", revision, backward }));
  }
  enterDocx(revision: number): EditState {
    return editState(this.call({ operation: "enterDocx", revision }));
  }

  findDocx(
    revision: number,
    text: string,
    options: DocxFindOptions = {},
  ): DocxSearchResult {
    checkFindOptions(options);
    return docxSearchResult(
      this.call({ operation: "findDocx", revision, text, options }),
    );
  }
  replaceDocxMatches(
    revision: number,
    matches: DocxSelection[],
    text: string,
  ): EditState {
    return editState(
      this.call({ operation: "replaceDocxMatches", revision, matches, text }),
    );
  }

  beginComposition(revision: number): EditState {
    return editState(this.call({ operation: "beginComposition", revision }));
  }

  updateComposition(
    revision: number,
    compositionId: number,
    text: string,
  ): EditState {
    return editState(
      this.call({
        operation: "updateComposition",
        revision,
        compositionId,
        text,
      }),
    );
  }

  commitComposition(
    revision: number,
    compositionId: number,
    text: string,
  ): EditState {
    return editState(
      this.call({
        operation: "commitComposition",
        revision,
        compositionId,
        text,
      }),
    );
  }

  cancelComposition(revision: number, compositionId: number): EditState {
    return editState(
      this.call({ operation: "cancelComposition", revision, compositionId }),
    );
  }

  selectDocx(revision: number, selection: DocxSelection): EditState {
    return editState(
      this.call({ operation: "selectDocx", revision, selection }),
    );
  }
  replaceRange(
    revision: number,
    selection: DocxSelection,
    text: string,
    inputGroup?: number,
  ): EditState {
    return editState(
      this.call({
        operation: "replaceRange",
        revision,
        selection,
        text,
        inputGroup,
      }),
    );
  }

  undoDocx(revision: number): EditState {
    return editState(this.call({ operation: "undoDocx", revision }));
  }

  deleteDocx(revision: number, direction: "backward" | "forward"): EditState {
    return editState(
      this.call({ operation: "deleteDocx", revision, direction }),
    );
  }

  redoDocx(revision: number): EditState {
    return editState(this.call({ operation: "redoDocx", revision }));
  }

  replaceNode(node: number, revision: number, text: string): number {
    const result = record(
      this.call({ operation: "replaceNode", node, revision, text }),
    );
    if (typeof result.revision !== "number")
      throw new Error("Invalid revision");
    return result.revision;
  }

  saveDocx(): Uint8Array {
    return this.bytes({ operation: "saveDocx" });
  }
  exportMarkup(
    revision: number,
    format: "html" | "markdown",
    outputBytes = 67108864,
  ): Uint8Array {
    return this.bytes({
      operation: "exportDocxMarkup",
      revision,
      format,
      outputBytes,
    });
  }

  flow(): DocxFlow {
    return docxFlow(this.call({ operation: "flow" }));
  }

  layout(profile: Record<string, string>): PageLayout {
    return pageLayout(this.call({ operation: "layout", profile }));
  }

  hitTest(layoutId: number, page: number, x: number, y: number): DocxHit {
    return docxHit(this.call({ operation: "hitTest", layoutId, page, x, y }));
  }

  caret(layoutId: number, position: DocxPosition): DocxHit {
    return docxHit(this.call({ operation: "caret", layoutId, position }));
  }

  navigateDocx(
    revision: number,
    layoutId: number,
    direction: NavigationDirection,
    extend = false,
  ): DocxNavigation {
    return docxNavigation(
      this.call({
        operation: "navigateDocx",
        revision,
        layoutId,
        direction,
        extend,
      }),
    );
  }

  selectionGeometry(
    layoutId: number,
    selection: DocxSelection,
  ): DocxSelectionGeometry {
    return docxSelectionGeometry(
      this.call({ operation: "selectionGeometry", layoutId, selection }),
    );
  }

  exportPdf(outputBytes: number, layoutId?: number): Uint8Array {
    return this.bytes({ operation: "exportPdf", outputBytes, layoutId });
  }

  imageBytes(key: string): Uint8Array {
    return this.bytes({ operation: "imageBytes", key });
  }

  addImage(
    key: string,
    width: number,
    height: number,
    rgba: Uint8Array,
  ): string {
    const result = record(
      this.call({
        operation: "image",
        key,
        width,
        height,
        bytes: encodeBytes(rgba),
      }),
    );
    if (typeof result.key !== "string" || !result.key)
      throw new Error("Invalid image resource identity");
    return result.key;
  }
}
export {
  docxNotes,
  checkDocxNoteEdit,
  checkDocxNoteCreate,
  checkDocxNoteIdentity,
  type DocxNotes,
  type DocxNoteKind,
  type DocxNoteEdit,
  type DocxNoteCreate,
  type DocxNoteIdentity,
} from "./docx-notes.js";
