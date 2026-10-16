import {
  checkFormatPatch,
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
  checkPageSetup,
  docxPageSettings,
  type DocxPageSetup,
  type DocxPageSettings,
  type DocxFormatting,
  type CharacterFormatPatch,
  type ParagraphFormatPatch,
} from "./docx-format.js";
export * from "./docx-format.js";
export * from "./docx-picture.js";
import {
  checkDocxPictureEdit,
  docxPictures,
  type DocxPictureEdit,
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
import { WasmSession, encodeBytes } from "./session.js";
import {
  checkDocxTableSize,
  checkDocxTableEdit,
  type DocxTableEdit,
} from "./docx-table.js";
export * from "./docx-table.js";
/** Logical soft line break; DOCX serializes it as w:br, while LF creates a paragraph. */
export const DOCX_SOFT_BREAK = "\u2028";
/** Logical page break; serialized as w:br w:type="page", never as an XML control character. */
export const DOCX_PAGE_BREAK = "\u000c";
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
  isDocxSelection,
  type DocxFindOptions,
  type DocxSearchResult,
} from "./docx-search.js";
export {
  checkFindOptions,
  docxSearchResult,
  type DocxFindOptions,
  type DocxSearchResult,
} from "./docx-search.js";

export interface Budget {
  fileBytes: number;
  entryBytes: number;
  totalBytes: number;
  retainedBytes: number;
  entries: number;
  xmlDepth: number;
  outputBytes: number;
}

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
  editable: boolean;
  reason: string;
  x: number;
  y: number;
  height: number;
}

export function docxHit(value: unknown): DocxHit {
  const object = record(value);
  const position = object.position === null ? null : record(object.position);
  if (
    !hasFields(
      value,
      ["reason"],
      ["layoutId", "revision", "page", "line", "x", "y", "height"],
    ) ||
    typeof object.editable !== "boolean" ||
    (position !== null &&
      (!hasFields(position, ["affinity"], ["paragraph", "offset"]) ||
        (position.bidiLevel !== undefined &&
          (typeof position.bidiLevel !== "number" ||
            !Number.isInteger(position.bidiLevel) ||
            position.bidiLevel < 0 ||
            position.bidiLevel > 126)) ||
        (position.frameStart !== undefined &&
          (typeof position.frameStart !== "number" ||
            !Number.isSafeInteger(position.frameStart) ||
            position.frameStart > 2147483647 ||
            position.frameStart <= Number(position.offset))) ||
        (position.affinity !== "before" && position.affinity !== "after"))) ||
    (object.editable === true && position === null)
  )
    throw new Error("Invalid DOCX hit returned by Wasm");
  return value as DocxHit;
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

export function docxSelectionGeometry(value: unknown): DocxSelectionGeometry {
  const object = record(value);
  const integer = (value: unknown): boolean =>
    typeof value === "number" && Number.isSafeInteger(value) && value >= 0;
  if (
    !integer(object.layoutId) ||
    !integer(object.revision) ||
    !Array.isArray(object.rects) ||
    !object.rects.every((value: unknown) => {
      const rect = record(value);
      return (
        integer(rect.page) &&
        integer(rect.line) &&
        hasFields(rect, [], ["x", "y", "width", "height"]) &&
        typeof rect.width === "number" &&
        rect.width >= 0 &&
        typeof rect.height === "number" &&
        rect.height > 0
      );
    })
  )
    throw new Error("Invalid DOCX selection geometry returned by Wasm");
  return value as DocxSelectionGeometry;
}

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

export interface EditState {
  revision: number;
  defaultTabStop: number;
  compositionId: number | null;
  selection: DocxSelection | null;
  canUndo: boolean;
  canRedo: boolean;
  affectedParagraphs: number[];
  historyBytes: number;
  historyEntries: number;
  historyEntryLimit: number;
  historyByteLimit: number;
  commandLimit: number;
  formatting: DocxFormatting | null;
}

export interface CreatedDocxStyle {
  id: string;
  state: EditState;
}

export function createdDocxStyle(value: unknown): CreatedDocxStyle {
  const result = record(value);
  if (typeof result.id !== "string" || !result.id || result.id.length > 200)
    throw new Error("Invalid created style identity");
  return { id: result.id, state: editState(result.state) };
}

export function editState(value: unknown): EditState {
  const object = record(value);
  const integer = (value: unknown): boolean =>
    typeof value === "number" && Number.isSafeInteger(value) && value >= 0;
  if (object.formatting !== null) docxFormatting(object.formatting);
  if (
    ![
      "revision",
      "historyBytes",
      "historyEntries",
      "historyEntryLimit",
      "historyByteLimit",
      "commandLimit",
    ].every((key) => integer(object[key])) ||
    (object.compositionId !== null &&
      (!integer(object.compositionId) || Number(object.compositionId) === 0)) ||
    typeof object.canUndo !== "boolean" ||
    typeof object.canRedo !== "boolean" ||
    typeof object.defaultTabStop !== "number" ||
    object.defaultTabStop < 0 ||
    object.defaultTabStop > 1584 ||
    !Number.isInteger(object.defaultTabStop * 20) ||
    !arrayOf(object.affectedParagraphs, integer) ||
    (object.selection !== null && !isDocxSelection(object.selection))
  )
    throw new Error("Invalid DOCX editing state returned by Wasm");
  return value as EditState;
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

export class DocumentError extends Error {
  constructor(
    readonly code: string,
    message: string,
    readonly part: string,
    readonly offset: number,
  ) {
    super(message);
    this.name = "DocumentError";
  }
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

export function resourceBudget(value: unknown): Budget {
  if (
    !hasFields(
      value,
      [],
      [
        "fileBytes",
        "entryBytes",
        "totalBytes",
        "retainedBytes",
        "entries",
        "xmlDepth",
        "outputBytes",
      ],
    )
  )
    throw new Error("Invalid resource budget returned by Wasm");
  return value as Budget;
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

export class FoundationSession extends WasmSession {
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
  ): EditState {
    copiedFormat(format);
    return editState(
      this.call({ operation: "applyFormat", revision, selection, format }),
    );
  }
  setCharacterFormat(
    revision: number,
    selection: DocxSelection,
    format: CharacterFormatPatch,
  ): EditState {
    checkFormatPatch(format);
    return editState(
      this.call({
        operation: "setCharacterFormat",
        revision,
        selection,
        format,
      }),
    );
  }
  setParagraphFormat(
    revision: number,
    selection: DocxSelection,
    format: ParagraphFormatPatch,
  ): EditState {
    checkFormatPatch(format, true);
    return editState(
      this.call({
        operation: "setParagraphFormat",
        revision,
        selection,
        format,
      }),
    );
  }

  editState(): EditState {
    return editState(this.call({ operation: "editState" }));
  }
  pageSetup(revision: number): DocxPageSettings {
    return docxPageSettings(this.call({ operation: "pageSetup", revision }));
  }
  pictures(revision: number) {
    return docxPictures(this.call({ operation: "docxPictures", revision }));
  }
  editPicture(revision: number, picture: DocxPictureEdit): EditState {
    checkDocxPictureEdit(picture);
    return editState(
      this.call({ operation: "editDocxPicture", revision, picture }),
    );
  }
  setPageSetup(revision: number, page: DocxPageSetup): EditState {
    checkPageSetup(page);
    return editState(this.call({ operation: "setPageSetup", revision, page }));
  }
  insertTable(
    revision: number,
    selection: DocxSelection,
    rows: number,
    columns: number,
  ): EditState {
    checkDocxTableSize(rows, columns);
    return editState(
      this.call({
        operation: "insertDocxTable",
        revision,
        selection,
        rows,
        columns,
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

  /** Reads bounded plain text in document order without changing core state. */
  selectedText(revision: number, selection: DocxSelection): string {
    const result = this.call({
      operation: "selectedText",
      revision,
      selection,
    });
    if (typeof result !== "string")
      throw new Error("Invalid selection text returned by Wasm");
    return result;
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
