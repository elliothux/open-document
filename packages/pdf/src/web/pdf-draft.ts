import type { PdfCommand, PdfTextSpec } from "../core/pdf.js";

export type EditCommand = Extract<
  PdfCommand,
  {
    operation:
      | "reorderPdfPages"
      | "rotatePdfPages"
      | "deletePdfPages"
      | "addPdfNote"
      | "highlightPdfText"
      | "updatePdfAnnotation"
      | "deletePdfAnnotation"
      | "setPdfFieldValue"
      | "setPdfMetadata"
      | "insertPdfPages"
      | "replacePdfPages"
      | "insertBlankPdfPage"
      | "cropPdfPage"
      | "resizePdfPage"
      | "addPdfText"
      | "replacePdfText"
      | "addPdfImage"
      | "movePdfObject"
      | "deletePdfObject"
      | "undoPdf"
      | "redoPdf";
  }
>;
export type Draft = {
  role?: PdfTextSpec["role"];
  pages?: string[];
  kind:
    | "field"
    | "annotation"
    | "note"
    | "metadata"
    | "textObject"
    | "newText"
    | "objectGeometry";
  originalSpec?: string;
  reason?: string;
  id: string;
  page: string;
  original: string | boolean;
};

export function pdfTextRole(value: string): PdfTextSpec["role"] {
  switch (value) {
    case "watermark":
    case "header":
    case "footer":
    case "page-number":
      return value;
    default:
      return "text";
  }
}

export function draftCommand(
  draft: Draft,
  value: string | boolean,
  spec: PdfTextSpec,
  x: number,
  y: number,
  revision: number,
  profile: Record<string, string>,
): EditCommand {
  switch (draft.kind) {
    case "newText":
      return {
        operation: "addPdfText",
        revision,
        pages: draft.pages ?? [draft.page],
        spec,
        profile,
      };
    case "textObject":
      return {
        operation: "replacePdfText",
        revision,
        page: draft.page,
        object: draft.id,
        spec,
        profile,
      };
    case "objectGeometry":
      return {
        operation: "movePdfObject",
        profile,
        revision,
        page: draft.page,
        object: draft.id,
        placement: spec.placement,
      };
    case "metadata":
      return {
        operation: "setPdfMetadata",
        revision,
        fields: { [draft.id]: String(value) },
      };
    case "field":
      return {
        operation: "setPdfFieldValue",
        revision,
        field: draft.id,
        value,
        profile,
      };
    case "annotation":
      return {
        operation: "updatePdfAnnotation",
        revision,
        page: draft.page,
        annotation: draft.id,
        text: String(value),
      };
    case "note":
      return {
        operation: "addPdfNote",
        revision,
        page: draft.page,
        x,
        y,
        text: String(value),
      };
  }
}
