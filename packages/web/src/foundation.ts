import { Connection } from "./connection.js";
export type {
  FormatValue,
  CharacterFormatPatch,
  ParagraphFormatPatch,
  DocxFormatting,
  DocxFindOptions,
  DocxOverview,
  DocxSearchResult,
  HighlightColor,
  CopiedFormat,
  DocxStyleUpdate,
  DocxStyleCreation,
  TabStop,
  DocxStyleCatalog,
  CreatedDocxStyle,
  DocxListReference,
  DocxListEdit,
  DocxListCatalog,
  DocxListLevel,
  DocxListLevelUpdate,
  DocxPageSetup,
  DocxPageSettings,
  DocxPicture,
  DocxPictureEdit,
  DocxPictureResizeCommand,
  DocxPictures,
  DocxTableEdit,
  DocxCellMargins,
  DocxBorderStyle,
  DocxBorderSide,
  DocxBorderPatch,
  DocxCellBorders,
  DocxTableBorders,
  DocxThemeSlot,
  DocxThemeColors,
  DocxThemeFonts,
  DocxThemeFontPair,
  ListFormat,
} from "@open-document/wasm/foundation";
export {
  checkDocxHyperlink,
  highlightColors,
  DOCX_SOFT_BREAK,
  DOCX_PAGE_BREAK,
  listFormats,
} from "@open-document/wasm/foundation";
import {
  docxFlow,
  pageLayout,
  type DocxFlow,
  type PageLayout,
} from "@open-document/wasm/preview";
import {
  docxQuery,
  docxThemeColors,
  docxThemeFonts,
  checkDocxThemeFonts,
  type DocxThemeFontPair,
  checkDocxThemeColor,
  type DocxThemeSlot,
  checkDocxTableSize,
  checkDocxTableEdit,
  type DocxTableEdit,
  shapeBatch,
  resourceBudget,
  editState,
  docxFormatting,
  checkDocxHyperlink,
  docxStyleCatalog,
  createdDocxStyle,
  type DocxStyleCatalog,
  copiedFormat,
  checkStyleUpdate,
  type CopiedFormat,
  type DocxStyleUpdate,
  type DocxStyleCreation,
  checkStyleCreation,
  checkDefaultTabStop,
  checkPageSetup,
  checkDocxPictureEdit,
  docxPictures,
  type DocxPictureEdit,
  type DocxPictureResizeCommand,
  checkDocxPictureResize,
  docxPageSettings,
  type DocxPageSetup,
  type DocxPageSettings,
  checkFormatPatch,
  checkListEdit,
  docxListCatalog,
  type DocxListEdit,
  checkListLevelUpdate,
  type DocxListLevelUpdate,
  checkFindOptions,
  docxSearchResult,
  docxOverview,
  type DocxOverview,
  type DocxFindOptions,
  type DocxSearchResult,
  type DocxFormatting,
  type CharacterFormatPatch,
  type ParagraphFormatPatch,
  docxHit,
  docxSelectionGeometry,
  docxNavigation,
  type DocxNavigation,
  type NavigationDirection,
  type DocxSelectionGeometry,
  type DocxHit,
  type DocxPosition,
  type EditState,
  type DocxSelection,
  type Budget,
  type DocxQuery,
  type ShapeBatch,
} from "@open-document/wasm/foundation";

/** Text shaping, bounded DOCX operations and preview/PDF, owned by one Worker. */
export class FoundationClient {
  private constructor(private readonly connection: Connection) {}

  static async open(
    wasm: ArrayBuffer,
    workerUrl: URL,
    signal?: AbortSignal,
  ): Promise<FoundationClient> {
    const client = new FoundationClient(
      new Connection(new Worker(workerUrl, { type: "module" })),
    );
    try {
      await client.connection.initialize(
        { operation: "openFoundation", wasm },
        signal,
      );
      return client;
    } catch (error) {
      client.dispose();
      throw error;
    }
  }
  async addFont(bytes: Uint8Array, identity: string): Promise<void> {
    await this.connection.request({ operation: "font", bytes, identity });
  }
  async defaultBudget(): Promise<Budget> {
    return resourceBudget(
      await this.connection.request({ operation: "budget" }),
    );
  }
  async shape(text: string, size = 32, language = "und"): Promise<ShapeBatch> {
    return shapeBatch(
      await this.connection.request({
        operation: "shape",
        text,
        size,
        language,
      }),
    );
  }
  async openDocx(bytes: Uint8Array, budget: Budget): Promise<DocxQuery> {
    return docxQuery(
      await this.connection.request({ operation: "openDocx", bytes, budget }),
    );
  }
  async query(): Promise<DocxQuery> {
    return docxQuery(await this.connection.request({ operation: "query" }));
  }
  async createDocx(budget: Budget): Promise<DocxQuery> {
    return docxQuery(
      await this.connection.request({ operation: "createDocx", budget }),
    );
  }
  async queryFormatting(
    revision: number,
    selection: DocxSelection,
  ): Promise<DocxFormatting> {
    return docxFormatting(
      await this.connection.request({
        operation: "queryFormatting",
        revision,
        selection,
      }),
    );
  }
  async lists(revision: number) {
    return docxListCatalog(
      await this.connection.request({ operation: "listCatalog", revision }),
    );
  }
  async themeColors(revision: number) {
    return docxThemeColors(
      await this.connection.request({ operation: "docxThemeColors", revision }),
    );
  }
  async themeFonts(revision: number) {
    return docxThemeFonts(
      await this.connection.request({ operation: "docxThemeFonts", revision }),
    );
  }
  async setThemeFonts(
    revision: number,
    fonts: DocxThemeFontPair,
    profile: Record<string, string>,
  ): Promise<EditState> {
    checkDocxThemeFonts(fonts);
    return editState(
      await this.connection.request({
        operation: "setDocxThemeFonts",
        revision,
        fonts,
        profile,
      }),
    );
  }
  async setThemeColor(
    revision: number,
    slot: DocxThemeSlot,
    color: string,
  ): Promise<EditState> {
    checkDocxThemeColor(slot, color);
    return editState(
      await this.connection.request({
        operation: "setDocxThemeColor",
        revision,
        slot,
        color,
      }),
    );
  }
  async editList(
    revision: number,
    selection: DocxSelection,
    change: DocxListEdit,
  ): Promise<EditState> {
    checkListEdit(change);
    return editState(
      await this.connection.request({
        operation: "editList",
        revision,
        selection,
        change,
      }),
    );
  }
  async updateListLevel(
    revision: number,
    id: number,
    level: number,
    definition: DocxListLevelUpdate,
  ): Promise<EditState> {
    checkListLevelUpdate(id, level, definition);
    return editState(
      await this.connection.request({
        operation: "updateListLevel",
        revision,
        listId: id,
        level,
        definition,
      }),
    );
  }
  async styles(
    revision: number,
    kind: "paragraph" | "character",
  ): Promise<DocxStyleCatalog> {
    return docxStyleCatalog(
      await this.connection.request({
        operation: "styleCatalog",
        revision,
        kind,
      }),
    );
  }
  async captureFormat(
    revision: number,
    selection: DocxSelection,
  ): Promise<CopiedFormat> {
    return copiedFormat(
      await this.connection.request({
        operation: "captureFormat",
        revision,
        selection,
      }),
    );
  }
  async updateStyle(
    revision: number,
    key: string,
    format: DocxStyleUpdate,
  ): Promise<EditState> {
    checkStyleUpdate(format);
    return editState(
      await this.connection.request({
        operation: "updateStyle",
        revision,
        key,
        format,
      }),
    );
  }
  async createStyle(revision: number, style: DocxStyleCreation) {
    checkStyleCreation(style);
    return createdDocxStyle(
      await this.connection.request({
        operation: "createStyle",
        revision,
        style,
      }),
    );
  }
  async pageSetup(revision: number): Promise<DocxPageSettings> {
    return docxPageSettings(
      await this.connection.request({ operation: "pageSetup", revision }),
    );
  }
  async pictures(revision: number) {
    return docxPictures(
      await this.connection.request({ operation: "docxPictures", revision }),
    );
  }
  async pictureResize(revision: number, change: DocxPictureResizeCommand) {
    checkDocxPictureResize(change);
    return editState(
      await this.connection.request({
        operation: "docxPictureResize",
        revision,
        change,
      }),
    );
  }
  async editPicture(
    revision: number,
    picture: DocxPictureEdit,
  ): Promise<EditState> {
    checkDocxPictureEdit(picture);
    return editState(
      await this.connection.request({
        operation: "editDocxPicture",
        revision,
        picture,
      }),
    );
  }
  async setPageSetup(
    revision: number,
    page: DocxPageSetup,
  ): Promise<EditState> {
    checkPageSetup(page);
    return editState(
      await this.connection.request({
        operation: "setPageSetup",
        revision,
        page,
      }),
    );
  }
  async insertTable(
    revision: number,
    selection: DocxSelection,
    rows: number,
    columns: number,
  ): Promise<EditState> {
    checkDocxTableSize(rows, columns);
    return editState(
      await this.connection.request({
        operation: "insertDocxTable",
        revision,
        selection,
        rows,
        columns,
      }),
    );
  }
  async setDefaultTabStop(
    revision: number,
    interval: number | null,
  ): Promise<EditState> {
    checkDefaultTabStop(interval);
    return editState(
      await this.connection.request({
        operation: "setDefaultTabStop",
        revision,
        interval,
      }),
    );
  }
  async editTable(
    revision: number,
    selection: DocxSelection,
    change: DocxTableEdit,
    profile: Record<string, string> = {},
  ): Promise<EditState> {
    checkDocxTableEdit(change);
    return editState(
      await this.connection.request({
        operation: "editDocxTable",
        revision,
        selection,
        change,
        profile,
      }),
    );
  }
  async deleteStyle(
    revision: number,
    key: string,
    replacement: string,
  ): Promise<EditState> {
    return editState(
      await this.connection.request({
        operation: "deleteStyle",
        revision,
        key,
        replacement,
      }),
    );
  }
  async applyFormat(
    revision: number,
    selection: DocxSelection,
    format: CopiedFormat,
  ): Promise<EditState> {
    copiedFormat(format);
    return editState(
      await this.connection.request({
        operation: "applyFormat",
        revision,
        selection,
        format,
      }),
    );
  }
  async setCharacterFormat(
    revision: number,
    selection: DocxSelection,
    format: CharacterFormatPatch,
  ): Promise<EditState> {
    checkFormatPatch(format);
    return editState(
      await this.connection.request({
        operation: "setCharacterFormat",
        revision,
        selection,
        format,
      }),
    );
  }
  async setHyperlink(
    revision: number,
    selection: DocxSelection,
    target: string | null,
    text?: string,
  ): Promise<EditState> {
    checkDocxHyperlink(target, text);
    return editState(
      await this.connection.request({
        operation: "setHyperlink",
        revision,
        selection,
        target,
        ...(text === undefined ? {} : { text }),
      }),
    );
  }
  async setParagraphFormat(
    revision: number,
    selection: DocxSelection,
    format: ParagraphFormatPatch,
  ): Promise<EditState> {
    checkFormatPatch(format, true);
    return editState(
      await this.connection.request({
        operation: "setParagraphFormat",
        revision,
        selection,
        format,
      }),
    );
  }
  async editState(): Promise<EditState> {
    return editState(await this.connection.request({ operation: "editState" }));
  }
  async tabDocx(revision: number, backward = false): Promise<EditState> {
    return editState(
      await this.connection.request({
        operation: "tabDocx",
        revision,
        backward,
      }),
    );
  }
  async enterDocx(revision: number): Promise<EditState> {
    return editState(
      await this.connection.request({ operation: "enterDocx", revision }),
    );
  }

  async overview(revision: number): Promise<DocxOverview> {
    return docxOverview(
      await this.connection.request({ operation: "docxOverview", revision }),
    );
  }
  async findDocx(
    revision: number,
    text: string,
    options: DocxFindOptions = {},
  ): Promise<DocxSearchResult> {
    checkFindOptions(options);
    return docxSearchResult(
      await this.connection.request({
        operation: "findDocx",
        revision,
        text,
        options,
      }),
    );
  }
  async replaceDocxMatches(
    revision: number,
    matches: DocxSelection[],
    text: string,
  ): Promise<EditState> {
    return editState(
      await this.connection.request({
        operation: "replaceDocxMatches",
        revision,
        matches,
        text,
      }),
    );
  }

  async beginComposition(revision: number): Promise<EditState> {
    return editState(
      await this.connection.request({
        operation: "beginComposition",
        revision,
      }),
    );
  }

  async updateComposition(
    revision: number,
    compositionId: number,
    text: string,
  ): Promise<EditState> {
    return editState(
      await this.connection.request({
        operation: "updateComposition",
        revision,
        compositionId,
        text,
      }),
    );
  }

  async commitComposition(
    revision: number,
    compositionId: number,
    text: string,
  ): Promise<EditState> {
    return editState(
      await this.connection.request({
        operation: "commitComposition",
        revision,
        compositionId,
        text,
      }),
    );
  }

  async cancelComposition(
    revision: number,
    compositionId: number,
  ): Promise<EditState> {
    return editState(
      await this.connection.request({
        operation: "cancelComposition",
        revision,
        compositionId,
      }),
    );
  }
  async selectDocx(
    revision: number,
    selection: DocxSelection,
  ): Promise<EditState> {
    return editState(
      await this.connection.request({
        operation: "selectDocx",
        revision,
        selection,
      }),
    );
  }
  async replaceRange(
    revision: number,
    selection: DocxSelection,
    text: string,
    inputGroup?: number,
  ): Promise<EditState> {
    return editState(
      await this.connection.request({
        operation: "replaceRange",
        revision,
        selection,
        text,
        inputGroup,
      }),
    );
  }
  async selectedText(
    revision: number,
    selection: DocxSelection,
    cut = false,
  ): Promise<string> {
    const result = await this.connection.request({
      operation: "selectedText",
      revision,
      selection,
      cut,
    });
    if (typeof result !== "string")
      throw new Error("Invalid selection text returned by Wasm");
    return result;
  }
  async undoDocx(revision: number): Promise<EditState> {
    return editState(
      await this.connection.request({ operation: "undoDocx", revision }),
    );
  }

  async deleteDocx(
    revision: number,
    direction: "backward" | "forward",
  ): Promise<EditState> {
    return editState(
      await this.connection.request({
        operation: "deleteDocx",
        revision,
        direction,
      }),
    );
  }
  async redoDocx(revision: number): Promise<EditState> {
    return editState(
      await this.connection.request({ operation: "redoDocx", revision }),
    );
  }
  async replaceNode(
    node: number,
    revision: number,
    text: string,
  ): Promise<number> {
    const result = await this.connection.request({
      operation: "replaceNode",
      node,
      revision,
      text,
    });
    if (typeof result !== "number")
      throw new Error("Invalid revision response");
    return result;
  }
  async saveDocx(): Promise<Uint8Array> {
    const result = await this.connection.request({ operation: "saveDocx" });
    if (!(result instanceof Uint8Array))
      throw new Error("Invalid byte response");
    return result;
  }
  async flow(): Promise<DocxFlow> {
    return docxFlow(await this.connection.request({ operation: "flow" }));
  }
  async layout(profile: Record<string, string>): Promise<PageLayout> {
    return pageLayout(
      await this.connection.request({ operation: "layout", profile }),
    );
  }

  async hitTest(
    layoutId: number,
    page: number,
    x: number,
    y: number,
  ): Promise<DocxHit> {
    return docxHit(
      await this.connection.request({
        operation: "hitTest",
        layoutId,
        page,
        x,
        y,
      }),
    );
  }

  async caret(layoutId: number, position: DocxPosition): Promise<DocxHit> {
    return docxHit(
      await this.connection.request({ operation: "caret", layoutId, position }),
    );
  }
  async exportPdf(outputBytes: number, layoutId?: number): Promise<Uint8Array> {
    const result = await this.connection.request({
      operation: "exportPdf",
      outputBytes,
      layoutId,
    });
    if (!(result instanceof Uint8Array)) throw new Error("Invalid PDF bytes");
    return result;
  }
  async navigateDocx(
    revision: number,
    layoutId: number,
    direction: NavigationDirection,
    extend = false,
  ): Promise<DocxNavigation> {
    return docxNavigation(
      await this.connection.request({
        operation: "navigateDocx",
        revision,
        layoutId,
        direction,
        extend,
      }),
    );
  }

  async selectionGeometry(
    layoutId: number,
    selection: DocxSelection,
  ): Promise<DocxSelectionGeometry> {
    return docxSelectionGeometry(
      await this.connection.request({
        operation: "selectionGeometry",
        layoutId,
        selection,
      }),
    );
  }

  async imageBytes(key: string): Promise<Uint8Array> {
    const result = await this.connection.request({
      operation: "imageBytes",
      key,
    });
    if (!(result instanceof Uint8Array)) throw new Error("Invalid image bytes");
    return result;
  }
  async addImage(
    key: string,
    width: number,
    height: number,
    bytes: Uint8Array,
  ): Promise<string> {
    const result = await this.connection.request({
      operation: "image",
      key,
      width,
      height,
      bytes,
    });
    if (typeof result !== "string" || !result)
      throw new Error("Invalid image resource identity");
    return result;
  }
  dispose(): void {
    this.connection.dispose();
  }
}
