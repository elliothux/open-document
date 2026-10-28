import type { DrawingBatch } from "@open-document/wasm/abi/drawing";

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
export interface PdfTextSpec {
  placement: PdfPlacement;
  text: string;
  font: string;
  size: number;
  color: string;
  role: "text" | "watermark" | "header" | "footer" | "page-number";
  foreground: boolean;
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
  kind: "text" | "checkbox" | "unsupported";
  value: string | boolean | null;
  readOnlyReason: string;
  multiline: boolean;
  maxLength: number;
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
      operation: "addPdfText";
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
  | { operation: "imagePdf"; layoutId: number; key: string }
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
      value: string | boolean;
      profile: Record<string, string>;
    }
  | { operation: "undoPdf" | "redoPdf"; revision: number }
  | { operation: "savePdf"; revision: number };

type Result<O extends PdfCommand["operation"]> = O extends "pdfObjects"
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
                      : O extends "imagePdf" | "decodedImagePdf"
                        ? PdfImage
                        : O extends "savePdf" | "extractPdfPages"
                          ? { revision: number; bytes: Uint8Array }
                          : PdfQuery;
export type PdfResult<C extends PdfCommand> = Result<C["operation"]>;
