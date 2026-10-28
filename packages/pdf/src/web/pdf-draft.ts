import type {
  PdfCommand,
  PdfTextSpec,
  PdfDrawingAnnotation,
  PdfFieldDesign,
  PdfFieldWidgetDesign,
  PdfAnnotationStyle,
  PdfImageCrop,
} from "../core/pdf.js";

export type EditCommand = Extract<
  PdfCommand,
  {
    operation:
      | "reorderPdfPages"
      | "rotatePdfPages"
      | "deletePdfPages"
      | "addPdfNote"
      | "highlightPdfText"
      | "markPdfText"
      | "addPdfDrawingAnnotation"
      | "editPdfAnnotation"
      | "replyPdfAnnotation"
      | "deletePdfAnnotationThread"
      | "addPdfInkAnnotation"
      | "addPdfStampAnnotation"
      | "updatePdfAnnotation"
      | "deletePdfAnnotation"
      | "setPdfFieldValue"
      | "setPdfMetadata"
      | "insertPdfPages"
      | "replacePdfPages"
      | "insertBlankPdfPage"
      | "cropPdfPage"
      | "resizePdfPage"
      | "splitPdfPage"
      | "splitPdfPageGrid"
      | "nupPdfPages"
      | "addPdfText"
      | "setPdfPageNumbers"
      | "createPdfField"
      | "updatePdfFieldDesign"
      | "renamePdfField"
      | "deletePdfField"
      | "duplicatePdfField"
      | "replacePdfText"
      | "addPdfImage"
      | "movePdfObject"
      | "cropPdfImage"
      | "deletePdfObject"
      | "undoPdf"
      | "redoPdf";
  }
>;
export type Draft = {
  pageAction?: "crop" | "resize" | "scale";
  drawingKind?: PdfDrawingAnnotation["kind"];
  arrow?: boolean;
  role?: PdfTextSpec["role"];
  pages?: string[];
  kind:
    | "field"
    | "annotation"
    | "note"
    | "metadata"
    | "textObject"
    | "newText"
    | "newDrawing"
    | "newField"
    | "newInk"
    | "fieldDesign"
    | "annotationStyle"
    | "annotationReply"
    | "fieldName"
    | "fieldCopy"
    | "pageGeometry"
    | "objectGeometry"
    | "imageCrop";
  originalSpec?: string;
  reason?: string;
  id: string;
  page: string;
  original: string | boolean | string[];
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
  value: string | boolean | string[],
  spec: PdfTextSpec,
  x: number,
  y: number,
  revision: number,
  profile: Record<string, string>,
  extra: {
    drawing?: PdfDrawingAnnotation | undefined;
    field?: PdfFieldDesign | undefined;
    widgets?: PdfFieldWidgetDesign[] | undefined;
    style?: PdfAnnotationStyle | undefined;
    ink?: { strokes: number[][]; signature: boolean } | undefined;
    crop?: PdfImageCrop | undefined;
  } = {},
): EditCommand {
  const { drawing, field } = extra;
  switch (draft.kind) {
    case "imageCrop":
      if (!extra.crop) throw new Error("Image crop draft is missing");
      return {
        operation: "cropPdfImage",
        revision,
        page: draft.page,
        object: draft.id,
        crop: extra.crop,
        profile,
      };
    case "newInk":
      if (!extra.ink || !extra.style) throw new Error("Ink draft is missing");
      return {
        operation: "addPdfInkAnnotation",
        revision,
        page: draft.page,
        style: extra.style,
        ...extra.ink,
      };
    case "annotationStyle":
      if (!extra.style) throw new Error("Annotation style is missing");
      return {
        operation: "editPdfAnnotation",
        revision,
        page: draft.page,
        annotation: draft.id,
        style: extra.style,
      };
    case "annotationReply":
      if (!extra.style) throw new Error("Annotation reply author is missing");
      return {
        operation: "replyPdfAnnotation",
        revision,
        page: draft.page,
        annotation: draft.id,
        text: String(value),
        author: extra.style.author,
      };
    case "fieldDesign":
      if (!field || !extra.widgets)
        throw new Error("Field design draft is missing");
      return {
        operation: "updatePdfFieldDesign",
        revision,
        field: draft.id,
        spec: field,
        widgets: extra.widgets,
        profile,
      };
    case "fieldCopy":
      return {
        operation: "duplicatePdfField",
        revision,
        field: draft.id,
        name: String(value),
        dx: x,
        dy: y,
      };
    case "fieldName":
      return {
        operation: "renamePdfField",
        revision,
        field: draft.id,
        name: String(value),
      };
    case "newField":
      if (!field) throw new Error("Field design draft is missing");
      return {
        operation: "createPdfField",
        revision,
        page: draft.page,
        spec: field,
        profile,
      };
    case "pageGeometry":
      return draft.pageAction === "crop"
        ? {
            operation: "cropPdfPage",
            revision,
            page: draft.page,
            x: spec.placement.x,
            y: spec.placement.y,
            width: spec.placement.width,
            height: spec.placement.height,
          }
        : {
            operation: "resizePdfPage",
            revision,
            page: draft.page,
            width: spec.placement.width,
            height: spec.placement.height,
            scaleContent: draft.pageAction === "scale",
            anchor: "top-left",
          };
    case "newDrawing":
      if (!drawing) throw new Error("Drawing annotation draft is missing");
      return {
        operation: "addPdfDrawingAnnotation",
        revision,
        page: draft.page,
        spec: drawing,
      };
    case "newText":
      return {
        operation:
          spec.role === "page-number" ? "setPdfPageNumbers" : "addPdfText",
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
