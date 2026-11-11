import type { PptxCommand } from "./pptx-command.js";
import { checkPptxImportInput, type PptxImportInfo } from "./pptx-import.js";
export { checkPptxImportInput } from "./pptx-import.js";
export type { PptxImportInfo } from "./pptx-import.js";
import type { PptxFragmentMedia } from "./pptx-media.js";
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
  type PptxShowState,
  type PptxShowLayout,
} from "./pptx-show.js";
export type {
  MathFormat,
  PptxMathTarget,
  PptxMathValue,
  PptxMathItem,
  PptxMathEdit,
} from "./pptx-math.js";
export type { PptxChart } from "./pptx-chart.js";
export { pptxInsertKinds } from "./pptx-object-edit.js";
import type { PptxMediaPlayback } from "./pptx-media.js";
export type {
  PptxMedia,
  PptxMediaPlayback,
  PptxFragmentMedia,
} from "./pptx-media.js";
export { mediaImageCommand } from "./pptx-show-media.js";
export type { PptxConnectorEnd, PptxConnector } from "./pptx-connectors.js";
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
  checkPptxObjectEdit,
  type PptxSelection,
  type PptxHit,
  type PptxGeometry,
  type PptxTable,
  type PptxHyperlink,
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
  type PptxPlaybackState,
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
  type PptxComments,
  type PptxComment,
  type PptxCommentAuthor,
} from "./pptx-slides.js";
import {
  OfficeSession,
  DocumentError,
  type InputLimits,
} from "@open-document/wasm/abi/session";
import { preparePptxSearch, type PptxSearchResult } from "./pptx-search.js";
export type { PptxFindOptions, PptxSearchResult } from "./pptx-search.js";
export { preparePptxSearch, pptxFindOptions } from "./pptx-search.js";
import { presentationDateTime } from "./pptx-clock.js";
import type { PptxFooter } from "./pptx-footer.js";
export type { PptxFooter, PptxFooterContent } from "./pptx-footer.js";
import type { PptxThemeColor, PptxThemeFont } from "./pptx-theme.js";
export type {
  PptxThemeColor,
  PptxThemeSlot,
  PptxThemeFont,
} from "./pptx-theme.js";
import type { PptxFormatting, PptxParagraphFormatting } from "./pptx-format.js";
export type {
  PptxTextFormat,
  PptxFormatting,
  PptxTextSpacing,
  PptxListFormat,
  PptxParagraphFormat,
  PptxParagraphTab,
  PptxParagraphFormatting,
} from "./pptx-format.js";
import type { PptxPrintLayout, PptxLayout } from "./pptx-output.js";
import type {
  EncodedImage,
  ImagePreparation,
  RasterHeader,
} from "@open-document/wasm/abi/drawing";
export type { PptxPrintLayout, PptxLayout } from "./pptx-output.js";

import type { PptxEditView, PptxGuides, PptxSnapping } from "./pptx-view.js";
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
type PreflightImage<C> = C extends
  { prepareImages: true } | { prepareResources: true }
  ? EncodedImage
  : ("prepareImages" | "prepareResources") & keyof C extends never
    ? string
    : EncodedImage | string;

type PreflightMedia<C> = C extends { prepareResources: true }
  ? Uint8Array
  : "prepareResources" extends keyof C
    ? Uint8Array | string
    : string;

interface FragmentResources<Bytes = Uint8Array> {
  images: EncodedImage<Bytes>[];
  media: PptxFragmentMedia<Bytes>[];
}

type Result<C extends PptxCommand> = C["operation"] extends "inspectPptxSlides"
  ? PptxImportInfo<PreflightImage<C>, PreflightMedia<C>>
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
                : C["operation"] extends "prepareImagePptx"
                  ? ImagePreparation
                  : C["operation"] extends
                        "savePptx" | "mediaBytesPptx" | "exportPptxPdf"
                    ? Uint8Array
                    : C["operation"] extends
                          "imageKeysPptx" | "imageKeysShowPptx"
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
                            ? PreflightImage<C>[]
                            : C["operation"] extends "objectFragmentMediaPptx"
                              ? PptxFragmentMedia[]
                              : C["operation"] extends "objectFragmentResourcesPptx"
                                ? FragmentResources
                                : PptxQuery;
export type PptxResult<C extends PptxCommand> =
  C["operation"] extends "rasterHeaderPptx" ? RasterHeader : Result<C>;

export { isPptxCommand } from "./pptx-command.js";

export interface PptxInputLimits extends InputLimits {
  readonly exportBytes: number;
  readonly textFragmentUnits: number;
  readonly objectFragmentUnits: number;
  readonly importBytes: number;
  readonly imageBytes: number;
  readonly mediaBytes: number;
  readonly rgbaBytes: number;
  readonly showInkBatchPoints: number;
}

/** Check host values and core-defined byte limits before platform work or encoding. */
export function checkPptxInput(
  command: PptxCommand,
  limits: PptxInputLimits,
): void {
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
    checkPptxShow(command, limits.showInkBatchPoints);
  if (command.operation === "editPptxObjects")
    checkPptxObjectEdit(command.change);
  if (command.operation === "editPptxSlides")
    checkPptxSlideEdit(command.change);
  if (command.operation === "pastePptxFragment")
    checkPptxTextFragment(command.fragment, limits.textFragmentUnits);
  if (
    command.operation === "pastePptxObjects" ||
    command.operation === "objectFragmentImagesPptx" ||
    command.operation === "objectFragmentMediaPptx" ||
    command.operation === "objectFragmentResourcesPptx"
  )
    checkPptxObjectFragment(command.fragment, limits.objectFragmentUnits);
  const check = (bytes: Uint8Array, ceiling: number): void => {
    if (bytes.length > ceiling)
      throw new DocumentError(
        "limit-exceeded",
        "PPTX input exceeds budget",
        "",
        -1,
      );
  };
  if (
    command.operation === "inspectPptxSlides" ||
    command.operation === "importPptxSlides"
  )
    check(command.bytes, limits.importBytes);
  else if (command.operation === "rasterHeaderPptx")
    check(command.bytes, limits.imageBytes);
  else if (command.operation === "imagePptx")
    check(command.bytes, limits.rgbaBytes);
  else if (command.operation === "openPptx")
    check(
      command.bytes,
      Math.min(command.budget.fileBytes, command.budget.retainedBytes),
    );
  else if (
    command.operation === "editPptxObjects" &&
    (command.change.action === "insertMedia" ||
      command.change.action === "fillMedia")
  ) {
    check(command.change.bytes, limits.mediaBytes);
    check(command.change.poster, limits.imageBytes);
  } else if (
    (command.operation === "editPptxObjects" &&
      (command.change.action === "insertImage" ||
        command.change.action === "imageFill" ||
        command.change.action === "replaceImage")) ||
    (command.operation === "editPptxSlides" &&
      command.change.action === "backgroundImage")
  )
    check(command.change.bytes, limits.imageBytes);
}

/** One presentation per core session. Commands retain format-specific semantics. */
export class PptxSession extends OfficeSession<PptxInputLimits> {
  constructor(exports: WebAssembly.Exports, handle: unknown) {
    super(exports, handle, "pptx");
  }

  execute<C extends PptxCommand>(command: C): PptxResult<C> {
    checkPptxInput(command, this.inputLimits());
    let value: unknown;
    if (
      command.operation === "findPptx" ||
      command.operation === "replacePptxMatches"
    )
      value = this.call(preparePptxSearch(command));
    else if (
      command.operation === "savePptx" ||
      command.operation === "mediaBytesPptx" ||
      command.operation === "exportPptxPdf"
    )
      value = this.bytes(command);
    else if (command.operation === "prepareImagePptx") {
      const image = this.call<ImagePreparation<number>>(command);
      value = { ...image, bytes: this.outputBytes(image.bytes) };
    } else if (command.operation === "inspectPptxSlides") {
      const info =
        this.call<PptxImportInfo<EncodedImage<number> | number, number>>(
          command,
        );
      value = {
        ...info,
        images: info.images.map((image) =>
          typeof image === "number"
            ? btoa(this.outputString(image))
            : this.readImage(image),
        ),
        media: info.media.map((clip) => ({
          ...clip,
          bytes:
            command.prepareResources === true
              ? this.outputBytes(clip.bytes)
              : btoa(this.outputString(clip.bytes)),
        })),
      };
    } else if (command.operation === "objectFragmentResourcesPptx") {
      const resources = this.call<FragmentResources<number>>(command);
      value = {
        images: resources.images.map((image) => this.readImage(image)),
        media: resources.media.map((clip) => ({
          ...clip,
          bytes: this.outputBytes(clip.bytes),
        })),
      };
    } else if (command.operation === "objectFragmentImagesPptx") {
      value =
        command.prepareImages === true
          ? this.call<EncodedImage<number>[]>(command).map((image) =>
              this.readImage(image),
            )
          : this.call<number[]>(command).map((slot) =>
              btoa(this.outputString(slot)),
            );
    } else if (command.operation === "objectFragmentMediaPptx") {
      value = this.call<PptxFragmentMedia<number>[]>(command).map((clip) => ({
        ...clip,
        bytes: btoa(this.outputString(clip.bytes)),
      }));
    } else if (
      command.operation === "openPptx" ||
      command.operation === "createPptx" ||
      command.operation === "dateTimePptx"
    )
      value = this.call({
        ...command,
        dateTime: presentationDateTime(command.dateTime),
      });
    else value = this.call(command);
    return value as PptxResult<C>;
  }

  private readImage(image: EncodedImage<number>): EncodedImage {
    return { ...image, bytes: this.outputBytes(image.bytes) };
  }
}
