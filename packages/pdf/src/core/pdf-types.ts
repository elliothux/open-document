import type { DrawingBatch } from "@open-document/wasm/abi/drawing";
import type { Budget } from "@open-document/wasm/abi/validation";
export type { Budget as PdfOfficeBudget } from "@open-document/wasm/abi/validation";

export interface PdfBudget {
  fileBytes: number;
  objects: number;
  objectNumber: number;
  pages: number;
  revisions: number;
  depth: number;
  streamBytes: number;
  decodedBytes: number;
  steps: number;
  outputBytes: number;
}
export interface PdfMetadata {
  revision: number;
  fields: Record<"Title" | "Author" | "Subject" | "Keywords", string>;
  readOnlyReason: string;
}
export interface PdfDestination {
  kind: "page" | "uri" | "blocked";
  page: string;
  uri: string;
  reason: string;
}
export interface PdfNavigation {
  revision: number;
  outlines: {
    id: string;
    title: string;
    level: number;
    target: PdfDestination;
  }[];
  links: {
    id: string;
    page: string;
    x: number;
    y: number;
    width: number;
    height: number;
    target: PdfDestination;
  }[];
}
export interface PdfRangeSelection {
  revision: number;
  text: string;
  pages: { page: string; start: number; end: number; quads: number[][] }[];
}
export interface PdfPlacement {
  x: number;
  y: number;
  width: number;
  height: number;
  rotation: number;
}
/** Normalized retained image window; appearance clipping preserves source pixels. */
export interface PdfImageCrop {
  x: number;
  y: number;
  width: number;
  height: number;
}
export interface PdfTextSpec {
  placement: PdfPlacement;
  text: string;
  font: string;
  size: number;
  color: string;
  role: "text" | "watermark" | "header" | "footer" | "page-number";
  foreground: boolean;
}
export interface PdfDrawingAnnotation {
  kind: "Square" | "Circle" | "Line" | "Ink";
  placement: PdfPlacement;
  points: number[];
  color: string;
  opacity: number;
  border: number;
  author: string;
  text: string;
  arrow: boolean;
}
export interface PdfAnnotationStyle {
  placement: PdfPlacement;
  color: string;
  opacity: number;
  border: number;
  author: string;
  text: string;
}
export interface PdfAnnotationDetails {
  revision: number;
  page: string;
  annotation: string;
  kind: string;
  style: PdfAnnotationStyle;
  points: number[];
  strokes: number[][];
  arrow: boolean;
  replyTo: string;
  signature: boolean;
}
export interface PdfAnnotationThread {
  revision: number;
  entries: {
    id: string;
    page: string;
    parent: string;
    text: string;
    author: string;
  }[];
}
export interface PdfFieldDesign {
  name: string;
  tooltip: string;
  kind: "text" | "checkbox" | "radio" | "choice" | "list";
  placement: PdfPlacement;
  options: { value: string; label: string }[];
  value: string | boolean | string[];
  defaultValue: string | boolean | string[];
  readOnly: boolean;
  required: boolean;
  multiline: boolean;
  multiSelect: boolean;
  maxLength: number;
  font: string;
  size: number;
  color: string;
  background: string;
  border: number;
}
export interface PdfFieldWidgetDesign {
  id: string;
  page: string;
  placement: PdfPlacement;
  border: number;
  borderColor: string;
  background: string;
  exportValue: string;
}
export interface PdfFieldDesignQuery {
  revision: number;
  field: string;
  spec: PdfFieldDesign | null;
  widgets: PdfFieldWidgetDesign[];
  readOnlyReason: string;
}
export interface PdfRedactionRegion {
  page: string;
  x: number;
  y: number;
  width: number;
  height: number;
}
export interface PdfRedactionAffected extends PdfRedactionRegion {
  kind: string;
}
export interface PdfRedactionPreview {
  revision: number;
  regions: PdfRedactionRegion[];
  affected: PdfRedactionAffected[];
  warnings: string[];
  readOnlyReason: string;
}
export interface PdfOfficeConversion {
  revision: number;
  format: "docx" | "xlsx" | "pptx";
  status: "success" | "completed-with-loss" | "needs-acceptance" | "failed";
  warnings: string[];
  reason: string;
  pages: { source: string; target: number }[];
  bytes: Uint8Array | null;
}
export interface PdfObject {
  foreground: boolean;
  id: string;
  kind: "text" | "image" | "unsupported";
  placement: PdfPlacement;
  text: string;
  font: string;
  size: number;
  color: string;
  role: string;
  readOnlyReason: string;
}
export interface PdfObjects {
  revision: number;
  page: string;
  objects: PdfObject[];
}
export interface PdfPage {
  id: string;
  object: number;
  generation: number;
  width: number;
  height: number;
  rotate: number;
}
export interface PdfAnnotation {
  id: string;
  page: string;
  kind: string;
  text: string;
  readOnlyReason: string;
}
export interface PdfField {
  id: string;
  name: string;
  kind: "text" | "checkbox" | "radio" | "choice" | "list" | "unsupported";
  value: string | boolean | string[] | null;
  multiSelect: boolean;
  readOnlyReason: string;
  multiline: boolean;
  maxLength: number;
  options: { value: string; label: string }[];
  widgets: { id: string; page: string }[];
}
export interface PdfQuery {
  revision: number;
  page: string;
  pages: PdfPage[];
  annotations: PdfAnnotation[];
  fields: PdfField[];
  readOnlyReason: string;
  pageOrderReason: string;
  canUndo: boolean;
  canRedo: boolean;
  historyBytes: number;
  modified: boolean;
  diagnostics: string[];
}
export interface PdfTextSpan {
  start: number;
  end: number;
  text: string;
  quad: number[];
  source: string;
  mapped: boolean;
  invisible: boolean;
}
export interface PdfText {
  page: string;
  revision: number;
  text: string;
  spans: PdfTextSpan[];
  complete: boolean;
  diagnostics: string[];
}
export interface PdfLayout extends DrawingBatch {
  reused?: boolean;
  id: number;
  page: string;
  revision: number;
  text: string;
  spans: PdfTextSpan[];
  textComplete: boolean;
  displayComplete: boolean;
  diagnostics: string[];
}
export interface PdfSearch {
  page: string;
  revision: number;
  complete: boolean;
  hits: { start: number; end: number; quads: number[][] }[];
  diagnostics: string[];
}
export interface PdfSelection {
  page: string;
  layoutId: number;
  revision: number;
  anchor: number;
  focus: number;
  quads: number[][];
}
export interface PdfHit {
  page: string;
  layoutId: number;
  revision: number;
  offset: number;
}
export interface PdfImage {
  kind: "rgba" | "jpeg";
  bytes: Uint8Array;
  width: number;
  height: number;
}
type PageRequest = {
  revision: number;
  page: string;
  profile: Record<string, string>;
};
export type PdfCommand =
  | { operation: "defaultPdfOfficeBudget" }
  | {
      operation: "convertPdfOffice";
      revision: number;
      pages: string[];
      format: "docx" | "xlsx" | "pptx";
      acceptLoss: boolean;
      profile: Record<string, string>;
      budget: Budget;
    }
  | {
      operation: "previewPdfRedaction" | "exportPdfRedaction";
      revision: number;
      regions: PdfRedactionRegion[];
      profile: Record<string, string>;
    }
  | { operation: "defaultPdfBudget" }
  | { operation: "openPdf"; bytes: Uint8Array; budget: PdfBudget }
  | { operation: "createPdf"; width: number; height: number; budget: PdfBudget }
  | { operation: "queryPdf" }
  | {
      operation: "pdfObjects";
      revision: number;
      page: string;
      profile: Record<string, string>;
    }
  | {
      operation: "addPdfText" | "setPdfPageNumbers";
      revision: number;
      pages: string[];
      spec: PdfTextSpec;
      profile: Record<string, string>;
    }
  | {
      operation: "replacePdfText";
      revision: number;
      page: string;
      object: string;
      spec: PdfTextSpec;
      profile: Record<string, string>;
    }
  | {
      operation: "addPdfImage";
      profile: Record<string, string>;
      replace?: string;
      revision: number;
      page: string;
      placement: PdfPlacement;
      pixelWidth: number;
      pixelHeight: number;
      bytes: Uint8Array;
    }
  | {
      operation: "cropPdfImage";
      revision: number;
      page: string;
      object: string;
      crop: PdfImageCrop;
      profile: Record<string, string>;
    }
  | {
      operation: "movePdfObject";
      profile: Record<string, string>;
      revision: number;
      page: string;
      object: string;
      placement: PdfPlacement;
    }
  | {
      operation: "deletePdfObject";
      profile: Record<string, string>;
      revision: number;
      page: string;
      object: string;
    }
  | {
      operation: "selectPdfRange";
      revision: number;
      anchorPage: string;
      anchor: number;
      focusPage: string;
      focus: number;
      profile: Record<string, string>;
    }
  | {
      operation: "selectedPdfRange";
      revision: number;
      profile: Record<string, string>;
    }
  | {
      operation: "cropPdfPage";
      revision: number;
      page: string;
      x: number;
      y: number;
      width: number;
      height: number;
    }
  | {
      operation: "resizePdfPage";
      revision: number;
      page: string;
      width: number;
      height: number;
      scaleContent: boolean;
      anchor: "top-left" | "center";
    }
  | { operation: "pdfNavigation" }
  | {
      operation: "insertPdfPages";
      revision: number;
      bytes: Uint8Array;
      pages: string[];
      index: number;
    }
  | {
      operation: "replacePdfPages";
      revision: number;
      bytes: Uint8Array;
      pages: string[];
      index: number;
      replace: string[];
    }
  | {
      operation: "insertBlankPdfPage";
      revision: number;
      width: number;
      height: number;
      index: number;
    }
  | { operation: "extractPdfPages"; revision: number; pages: string[] }
  | {
      operation: "renamePdfField";
      revision: number;
      field: string;
      name: string;
    }
  | { operation: "deletePdfField"; revision: number; field: string }
  | {
      operation: "duplicatePdfField";
      revision: number;
      field: string;
      name: string;
      dx: number;
      dy: number;
    }
  | {
      operation: "createPdfField";
      revision: number;
      page: string;
      spec: PdfFieldDesign;
      profile: Record<string, string>;
    }
  | { operation: "splitPdfFiles"; revision: number; groups: string[][] }
  | {
      operation: "pdfAnnotation" | "pdfAnnotationThread";
      revision: number;
      page: string;
      annotation: string;
    }
  | {
      operation: "editPdfAnnotation";
      revision: number;
      page: string;
      annotation: string;
      style: PdfAnnotationStyle;
    }
  | {
      operation: "replyPdfAnnotation";
      revision: number;
      page: string;
      annotation: string;
      text: string;
      author: string;
    }
  | {
      operation: "deletePdfAnnotationThread";
      revision: number;
      page: string;
      annotation: string;
    }
  | {
      operation: "addPdfInkAnnotation";
      revision: number;
      page: string;
      style: PdfAnnotationStyle;
      strokes: number[][];
      signature: boolean;
    }
  | {
      operation: "addPdfStampAnnotation";
      revision: number;
      page: string;
      style: PdfAnnotationStyle;
      pixelWidth: number;
      pixelHeight: number;
      bytes: Uint8Array;
      signature: boolean;
    }
  | { operation: "pdfFieldDesign"; revision: number; field: string }
  | {
      operation: "updatePdfFieldDesign";
      revision: number;
      field: string;
      spec: PdfFieldDesign;
      widgets: PdfFieldWidgetDesign[];
      profile: Record<string, string>;
    }
  | {
      operation: "splitPdfPage";
      revision: number;
      page: string;
      regions: PdfPlacement[];
    }
  | {
      operation: "splitPdfPageGrid";
      revision: number;
      page: string;
      columns: number;
      rows: number;
    }
  | {
      operation: "nupPdfPages";
      revision: number;
      pages: string[];
      columns: number;
      rows: number;
      width: number;
      height: number;
    }
  | {
      operation: "exportPdfText";
      revision: number;
      pages: string[];
      format: "html" | "markdown";
      profile: Record<string, string>;
    }
  | { operation: "pdfMetadata" }
  | {
      operation: "setPdfMetadata";
      revision: number;
      fields: Partial<PdfMetadata["fields"]>;
    }
  | ({
      operation: "renderPdfPage";
      activate?: boolean;
      reuse?: boolean;
    } & PageRequest)
  | ({ operation: "extractPdfText" } & PageRequest)
  | { operation: "releasePdfView"; layoutId: number }
  | ({ operation: "searchPdfPage"; query: string } & PageRequest)
  | { operation: "hitTestPdf"; layoutId: number; x: number; y: number }
  | { operation: "selectPdf"; layoutId: number; anchor: number; focus: number }
  | { operation: "selectedPdfText"; layoutId: number }
  | {
      operation: "imagePdf";
      layoutId: number;
      key: string;
      size?: { width: number; height: number };
    }
  | {
      operation: "decodedImagePdf";
      layoutId: number;
      key: string;
      width: number;
      height: number;
      bytes: Uint8Array;
    }
  | {
      operation: "reorderPdfPages" | "deletePdfPages";
      revision: number;
      pages: string[];
    }
  | {
      operation: "rotatePdfPages";
      revision: number;
      pages: string[];
      degrees: number;
    }
  | {
      operation: "addPdfNote";
      revision: number;
      page: string;
      x: number;
      y: number;
      text: string;
    }
  | { operation: "highlightPdfText"; revision: number; layoutId: number }
  | {
      operation: "markPdfText";
      revision: number;
      layoutId: number;
      kind: "Highlight" | "Underline" | "StrikeOut";
    }
  | {
      operation: "addPdfDrawingAnnotation";
      revision: number;
      page: string;
      spec: PdfDrawingAnnotation;
    }
  | {
      operation: "updatePdfAnnotation";
      revision: number;
      page: string;
      annotation: string;
      text: string;
    }
  | {
      operation: "deletePdfAnnotation";
      revision: number;
      page: string;
      annotation: string;
    }
  | {
      operation: "setPdfFieldValue";
      revision: number;
      field: string;
      value: string | boolean | string[];
      profile: Record<string, string>;
    }
  | { operation: "undoPdf" | "redoPdf"; revision: number }
  | { operation: "savePdf"; revision: number };

type Result<O extends PdfCommand["operation"]> =
  O extends "defaultPdfOfficeBudget"
    ? Budget
    : O extends "convertPdfOffice"
      ? PdfOfficeConversion
      : O extends "previewPdfRedaction"
        ? PdfRedactionPreview
        : O extends "exportPdfRedaction"
          ? { revision: number; bytes: Uint8Array; warnings: string[] }
          : O extends "pdfAnnotation"
            ? PdfAnnotationDetails
            : O extends "pdfAnnotationThread"
              ? PdfAnnotationThread
              : O extends "pdfFieldDesign"
                ? PdfFieldDesignQuery
                : O extends "splitPdfFiles"
                  ? {
                      revision: number;
                      files: { name: string; bytes: Uint8Array }[];
                    }
                  : O extends "exportPdfText"
                    ? {
                        revision: number;
                        bytes: Uint8Array;
                        warnings: string[];
                      }
                    : O extends "pdfObjects"
                      ? PdfObjects
                      : O extends "selectPdfRange" | "selectedPdfRange"
                        ? PdfRangeSelection
                        : O extends "pdfNavigation"
                          ? PdfNavigation
                          : O extends "pdfMetadata"
                            ? PdfMetadata
                            : O extends "defaultPdfBudget"
                              ? PdfBudget
                              : O extends "renderPdfPage"
                                ? PdfLayout
                                : O extends "extractPdfText"
                                  ? PdfText
                                  : O extends "searchPdfPage"
                                    ? PdfSearch
                                    : O extends "hitTestPdf"
                                      ? PdfHit
                                      : O extends "selectPdf"
                                        ? PdfSelection
                                        : O extends "selectedPdfText"
                                          ? { text: string }
                                          : O extends
                                                "imagePdf" | "decodedImagePdf"
                                            ? PdfImage
                                            : O extends
                                                  "savePdf" | "extractPdfPages"
                                              ? {
                                                  revision: number;
                                                  bytes: Uint8Array;
                                                }
                                              : PdfQuery;
export type PdfResult<C extends PdfCommand> = Result<C["operation"]>;
