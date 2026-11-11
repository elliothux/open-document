import type { EngineHandle } from "@open-document/wasm";
import { verifyEncodedImage } from "@open-document/web-core/image";
import { verifyPresentationMedia } from "./presentation-media.js";
export { preparePresentationMedia } from "./presentation-media.js";
import { type PptxCommand, type PptxResult } from "../core/pptx.js";
export type {
  PptxInputLimits,
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
import { PptxWorkerSession } from "../headless.js";

import { checkViewCommand } from "@open-document/web-core/view-mode";

const viewCommands = new Set<PptxCommand["operation"]>([
  "queryPptx",
  "layoutPptx",
  "selectionPptx",
  "selectPptx",
  "navigatePptx",
  "hitPptx",
  "findPptx",
  "copyPptx",
  "savePptx",
  "exportPptxPdf",
  "printLayoutPptx",
  "previewKeysPptx",
  "previewPptx",
  "imageKeysPptx",
  "imagePptx",
  "prepareImagePptx",
  "mediaBytesPptx",
  "followPptxHyperlink",
  "rasterHeaderPptx",
  "layoutShowPptx",
  "imageKeysShowPptx",
  "mediaShowPptx",
  "controlShowPptx",
  "cancelPptx",
]);

export class PptxClient extends PptxWorkerSession {
  readOnly = false;

  protected override checkCommand(command: PptxCommand): void {
    checkViewCommand(this.readOnly, viewCommands, command.operation);
    super.checkCommand(command);
  }

  private readonly events = new AbortController();
  static override async open(
    engine: EngineHandle,
    workerUrl: URL,
    signal?: AbortSignal,
  ): Promise<PptxClient> {
    return new PptxClient(await this.connect(engine, workerUrl, signal));
  }
  override async execute<C extends PptxCommand>(
    command: C,
  ): Promise<PptxResult<C>> {
    this.checkCommand(command);
    if (
      command.operation === "inspectPptxSlides" ||
      command.operation === "importPptxSlides"
    ) {
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
        prepareResources: true,
        verifyImages: true,
      });
      for (const image of info.images)
        await verifyEncodedImage(image.bytes, image.header, this.events.signal);
      for (const media of info.media)
        await verifyPresentationMedia(
          media.bytes,
          media.kind,
          media.contentType,
          this.inputLimits(),
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
      command.operation === "editPptxObjects" &&
      (command.change.action === "insertMedia" ||
        command.change.action === "fillMedia")
    ) {
      const poster = new Uint8Array(command.change.poster);
      const before =
        command.change.action === "fillMedia"
          ? await this.execute({ operation: "queryPptx" })
          : null;
      await verifyPresentationMedia(
        command.change.bytes,
        command.change.kind,
        command.change.contentType,
        this.inputLimits(),
        this.events.signal,
      );
      await this.verifyRaster(poster);
      if (before) {
        const after = await this.execute({ operation: "queryPptx" });
        if (
          after.revision !== command.revision ||
          JSON.stringify(after.selection) !== JSON.stringify(before.selection)
        )
          throw new Error("Selection changed during media preparation");
      }
      command = { ...command, change: { ...command.change, poster } };
    }
    if (command.operation === "pastePptxObjects") {
      const before = await this.execute({ operation: "queryPptx" });
      const { images, media } = await this.execute({
        operation: "objectFragmentResourcesPptx",
        revision: command.revision,
        fragment: command.fragment,
        verifyImages: true,
      });
      for (const image of images)
        await verifyEncodedImage(image.bytes, image.header, this.events.signal);
      for (const clip of media)
        await verifyPresentationMedia(
          clip.bytes,
          clip.kind,
          clip.contentType,
          this.inputLimits(),
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
      const bytes = new Uint8Array(command.change.bytes);
      await this.verifyRaster(bytes);
      command = { ...command, change: { ...command.change, bytes } };
    }
    return super.execute(command);
  }
  private async verifyRaster(bytes: Uint8Array): Promise<void> {
    const header = await this.execute({
      operation: "rasterHeaderPptx",
      bytes,
      verify: true,
    });
    await verifyEncodedImage(bytes, header, this.events.signal);
  }
  override dispose(): void {
    this.events.abort();
    super.dispose();
  }
}
