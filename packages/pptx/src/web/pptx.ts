import type { EngineHandle } from "@open-document/wasm";
import { engineModule } from "@open-document/wasm/loader";
import type { Operation } from "../worker/protocol.js";
import { Connection } from "@open-document/web-core/connection";
import { decodeImage } from "@open-document/web-core/image";
import { verifyPresentationMedia } from "./presentation-media.js";
export { preparePresentationMedia } from "./presentation-media.js";
import {
  pptxResult,
  checkPptxObjectEdit,
  checkPptxSlideEdit,
  preparePptxSearch,
  checkPptxShow,
  checkPptxTextFragment,
  checkPptxObjectFragment,
  checkPptxImportInput,
  type PptxCommand,
  type PptxResult,
} from "../core/pptx.js";
import { resourceBudget, type Budget } from "@open-document/wasm/abi/session";
export type {
  MathFormat,
  PptxMathTarget,
  PptxMathValue,
  PptxMathItem,
  PptxMathEdit,
  PptxQuery,
  PptxChart,
  PptxGuide,
  PptxSpacing,
  PptxSizeMatch,
  PptxGuides,
  PptxSnapSettings,
  PptxSnapping,
  PptxMedia,
  PptxMediaPlayback,
  PptxFragmentMedia,
  PptxImportInfo,
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
} from "../core/pptx.js";
export {
  checkPptxSlideEdit,
  pptxPlaceholderTypes,
  pptxInsertKinds,
} from "../core/pptx.js";

/** A Worker owns presentation state, layout, history and source bytes. */
export class PptxClient {
  private readonly events = new AbortController();
  private constructor(private readonly connection: Connection<Operation>) {}
  static async open(
    engine: EngineHandle,
    workerUrl: URL,
    signal?: AbortSignal,
  ): Promise<PptxClient> {
    const client = new PptxClient(
      new Connection<Operation>(new Worker(workerUrl, { type: "module" })),
    );
    try {
      await client.connection.initialize(
        { operation: "initialize", module: engineModule(engine) },
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
      command.operation === "inspectPptxSlides" ||
      command.operation === "importPptxSlides"
    ) {
      checkPptxImportInput(
        command.bytes,
        command.indices,
        command.operation === "importPptxSlides",
      );
      command = {
        ...command,
        bytes: new Uint8Array(command.bytes),
        indices: [...command.indices],
      };
    }
    if (command.operation === "importPptxSlides") {
      const before = await this.execute({ operation: "queryPptx" });
      const info = await this.execute({
        operation: "inspectPptxSlides",
        revision: command.revision,
        bytes: command.bytes,
        indices: command.indices,
      });
      for (const image of info.images) {
        const { bitmap } = await decodeImage(
          Uint8Array.from(atob(image), (c) => c.charCodeAt(0)),
          this.events.signal,
        );
        bitmap.close();
      }
      for (const media of info.media)
        await verifyPresentationMedia(
          Uint8Array.from(atob(media.bytes), (c) => c.charCodeAt(0)),
          media.kind,
          media.contentType,
          this.events.signal,
        );
      const after = await this.execute({ operation: "queryPptx" });
      if (
        after.revision !== command.revision ||
        JSON.stringify(after.selection) !== JSON.stringify(before.selection)
      )
        throw new Error("Selection changed during slide import preparation");
    }
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
      (command.change.action === "insertMedia" ||
        command.change.action === "fillMedia")
    ) {
      const before =
        command.change.action === "fillMedia"
          ? await this.execute({ operation: "queryPptx" })
          : null;
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
      if (before) {
        const after = await this.execute({ operation: "queryPptx" });
        if (
          after.revision !== command.revision ||
          JSON.stringify(after.selection) !== JSON.stringify(before.selection)
        )
          throw new Error("Selection changed during media preparation");
      }
    }
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
    if (command.operation === "pastePptxObjects") {
      const before = await this.execute({ operation: "queryPptx" });
      const images = await this.execute({
        operation: "objectFragmentImagesPptx",
        revision: command.revision,
        fragment: command.fragment,
      });
      for (const encoded of images) {
        const bytes = Uint8Array.from(atob(encoded), (character) =>
          character.charCodeAt(0),
        );
        const { bitmap } = await decodeImage(bytes, this.events.signal);
        bitmap.close();
      }
      const media = await this.execute({
        operation: "objectFragmentMediaPptx",
        revision: command.revision,
        fragment: command.fragment,
      });
      for (const clip of media)
        await verifyPresentationMedia(
          Uint8Array.from(atob(clip.bytes), (character) =>
            character.charCodeAt(0),
          ),
          clip.kind,
          clip.contentType,
          this.events.signal,
        );
      const after = await this.execute({ operation: "queryPptx" });
      if (
        after.revision !== command.revision ||
        JSON.stringify(after.selection) !== JSON.stringify(before.selection)
      )
        throw new Error("Selection changed during object paste preparation");
    }
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
