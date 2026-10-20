import { Connection } from "./connection.js";
import { decodeImage } from "./image.js";
import { verifyPresentationMedia } from "./presentation-media.js";
export { preparePresentationMedia } from "./presentation-media.js";
import {
  pptxResult,
  checkPptxObjectEdit,
  checkPptxSlideEdit,
  preparePptxSearch,
  checkPptxShow,
  type PptxCommand,
  type PptxResult,
} from "@open-document/wasm/pptx";
import { resourceBudget, type Budget } from "@open-document/wasm/foundation";
export type {
  PptxQuery,
  PptxGuide,
  PptxGuides,
  PptxSnapSettings,
  PptxSnapping,
  PptxMedia,
  PptxMediaPlayback,
  PptxPlaceholder,
  PptxPlaceholderType,
  PptxEditView,
  PptxMasterTextStyle,
  PptxMasterTextStyles,
  PptxMasterParagraphFormat,
  PptxMasterParagraphStyle,
  PptxTable,
  PptxTableStyle,
  PptxTransition,
  PptxAdvance,
  PptxAnimation,
  PptxShowAction,
  PptxShowState,
  PptxShowLayout,
  PptxShowInkChange,
  PptxShowMediaChange,
  PptxShowMediaState,
  PptxThemeColor,
  PptxThemeFont,
  PptxThemeSlot,
  PptxObjectEdit,
  PptxConnectorEnd,
  PptxConnector,
  PptxHyperlink,
  PptxDash,
  PptxCap,
  PptxLineEnd,
  PptxJoin,
  PptxFindOptions,
  PptxSearchResult,
  PptxSlideEdit,
  PptxFooter,
  PptxFooterContent,
  PptxCommentAuthor,
  PptxComment,
  PptxComments,
  PptxBackgroundFill,
  PptxBackground,
  PptxSection,
  PptxSections,
  PptxSlideLayouts,
  PptxTextFormat,
  PptxFormatting,
  PptxTextSpacing,
  PptxListFormat,
  PptxParagraphFormat,
  PptxParagraphTab,
  PptxParagraphFormatting,
} from "@open-document/wasm/pptx";
export {
  checkPptxSlideEdit,
  pptxPlaceholderTypes,
} from "@open-document/wasm/pptx";

/** A Worker owns presentation state, layout, history and source bytes. */
export class PptxClient {
  private readonly events = new AbortController();
  private constructor(private readonly connection: Connection) {}
  static async open(
    wasm: ArrayBuffer,
    workerUrl: URL,
    signal?: AbortSignal,
  ): Promise<PptxClient> {
    const client = new PptxClient(
      new Connection(new Worker(workerUrl, { type: "module" })),
    );
    try {
      await client.connection.initialize(
        { operation: "openPresentation", wasm },
        signal,
      );
      return client;
    } catch (error) {
      client.dispose();
      throw error;
    }
  }
  async defaultBudget(): Promise<Budget> {
    return resourceBudget(
      await this.connection.request({ operation: "budget" }),
    );
  }
  async addFont(bytes: Uint8Array, identity: string): Promise<void> {
    await this.connection.request({ operation: "font", bytes, identity });
  }
  async execute<C extends PptxCommand>(command: C): Promise<PptxResult<C>> {
    if (
      command.operation === "controlShowPptx" ||
      command.operation === "inkShowPptx" ||
      command.operation === "mediaShowPptx" ||
      command.operation === "layoutShowPptx"
    )
      checkPptxShow(command);
    if (command.operation === "editPptxObjects")
      checkPptxObjectEdit(command.change);
    if (
      command.operation === "editPptxObjects" &&
      command.change.action === "insertMedia"
    ) {
      await verifyPresentationMedia(
        command.change.bytes,
        command.change.kind,
        command.change.contentType,
        this.events.signal,
      );
      const { bitmap } = await decodeImage(
        command.change.poster,
        this.events.signal,
      );
      bitmap.close();
    }
    if (command.operation === "editPptxSlides")
      checkPptxSlideEdit(command.change);
    if (
      (command.operation === "editPptxObjects" &&
        (command.change.action === "insertImage" ||
          command.change.action === "imageFill" ||
          command.change.action === "replaceImage")) ||
      (command.operation === "editPptxSlides" &&
        command.change.action === "backgroundImage")
    ) {
      const { bitmap } = await decodeImage(command.change.bytes);
      bitmap.close();
    }
    const request =
      command.operation === "findPptx" ||
      command.operation === "replacePptxMatches"
        ? preparePptxSearch(command)
        : command;
    return pptxResult(command, await this.connection.request(request));
  }
  dispose(): void {
    this.events.abort();
    this.connection.dispose();
  }
}
