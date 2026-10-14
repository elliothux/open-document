import { WasmSession, encodeBytes } from "./session.js";
import { record } from "./validation.js";
import { drawingBatch, type DrawingBatch } from "./drawing.js";

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
  | { operation: "queryPdf" }
  | ({ operation: "renderPdfPage" | "extractPdfText" } & PageRequest)
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

type Result<O extends PdfCommand["operation"]> = O extends "defaultPdfBudget"
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
                : O extends "savePdf"
                  ? { revision: number; bytes: Uint8Array }
                  : PdfQuery;
export type PdfResult<C extends PdfCommand> = Result<C["operation"]>;

const operations: ReadonlySet<string> = new Set([
  "defaultPdfBudget",
  "openPdf",
  "queryPdf",
  "renderPdfPage",
  "extractPdfText",
  "searchPdfPage",
  "hitTestPdf",
  "selectPdf",
  "selectedPdfText",
  "imagePdf",
  "decodedImagePdf",
  "reorderPdfPages",
  "rotatePdfPages",
  "deletePdfPages",
  "addPdfNote",
  "highlightPdfText",
  "updatePdfAnnotation",
  "deletePdfAnnotation",
  "setPdfFieldValue",
  "undoPdf",
  "redoPdf",
  "savePdf",
]);
export function isPdfCommand(value: {
  operation: string;
}): value is PdfCommand {
  return operations.has(value.operation);
}
function integer(value: unknown, max = 0x7fffffff): number {
  if (
    typeof value !== "number" ||
    !Number.isInteger(value) ||
    value < 0 ||
    value > max
  )
    throw new Error("Invalid PDF integer");
  return value;
}
function text(value: unknown, max = 32767): string {
  if (typeof value !== "string" || value.length > max)
    throw new Error("Invalid PDF text");
  return value;
}
function bool(value: unknown): void {
  if (typeof value !== "boolean") throw new Error("Invalid PDF boolean");
}
function array(value: unknown, max: number): unknown[] {
  if (!Array.isArray(value) || value.length > max)
    throw new Error("Invalid PDF array");
  return value;
}
function quad(value: unknown): void {
  const points = array(value, 8);
  if (
    points.length !== 8 ||
    points.some(
      (p) => typeof p !== "number" || !Number.isFinite(p) || Math.abs(p) > 1e9,
    )
  )
    throw new Error("Invalid PDF quadrilateral");
}
function diagnostics(value: unknown): void {
  for (const message of array(value, 1048576)) text(message);
}
function spans(value: unknown, length: number): void {
  for (const entry of array(value, 1048576)) {
    const span = record(entry);
    if (integer(span.start, length) > integer(span.end, length))
      throw new Error("Invalid PDF source range");
    text(span.text, 262144);
    text(span.source, 4096);
    bool(span.mapped);
    bool(span.invisible);
    quad(span.quad);
  }
}
function query(value: unknown): void {
  const state = record(value);
  integer(state.revision);
  text(state.page, 256);
  text(state.readOnlyReason);
  text(state.pageOrderReason);
  bool(state.canUndo);
  bool(state.canRedo);
  bool(state.modified);
  integer(state.historyBytes, 8388608);
  const ids = new Set<string>();
  for (const entry of array(state.pages, 1024)) {
    const page = record(entry);
    const id = text(page.id, 256);
    if (!id || ids.has(id)) throw new Error("Invalid PDF page identity");
    ids.add(id);
    integer(page.object, 1000000);
    integer(page.generation, 65535);
    if (![0, 90, 180, 270].includes(integer(page.rotate, 270)))
      throw new Error("Invalid PDF page rotation");
    for (const key of ["width", "height"])
      if (
        typeof page[key] !== "number" ||
        !Number.isFinite(page[key]) ||
        page[key] <= 0 ||
        page[key] > 14400
      )
        throw new Error("Invalid PDF page size");
  }
  if (!ids.has(String(state.page)))
    throw new Error("PDF current page is missing");
  for (const entry of array(state.annotations, 4096)) {
    const item = record(entry);
    for (const key of ["id", "page", "kind", "text", "readOnlyReason"])
      text(item[key]);
    if (!ids.has(String(item.page))) throw new Error("Invalid annotation page");
  }
  for (const entry of array(state.fields, 4096)) {
    const field = record(entry);
    for (const key of ["id", "name", "readOnlyReason"]) text(field[key]);
    if (!["text", "checkbox", "unsupported"].includes(String(field.kind)))
      throw new Error("Invalid PDF field kind");
    if (field.kind === "text") text(field.value);
    else if (field.kind === "checkbox") bool(field.value);
    else if (field.value !== null)
      throw new Error("Invalid protected PDF field");
    bool(field.multiline);
    integer(field.maxLength, 32767);
    for (const widget of array(field.widgets, 4096)) {
      const item = record(widget);
      text(item.id, 256);
      text(item.page, 256);
      if (item.page !== "" && !ids.has(String(item.page)))
        throw new Error("Invalid widget page");
    }
  }
  diagnostics(state.diagnostics);
}
function bytes(value: unknown, limit: number): Uint8Array {
  if (value instanceof Uint8Array) {
    if (value.length > limit) throw new Error("PDF bytes exceed budget");
    return value;
  }
  if (typeof value !== "string" || value.length > Math.ceil(limit / 3) * 4)
    throw new Error("Invalid PDF bytes");
  const decoded = Uint8Array.from(atob(value), (c) => c.charCodeAt(0));
  if (decoded.length > limit) throw new Error("PDF bytes exceed budget");
  return decoded;
}
export function pdfResult<C extends PdfCommand>(
  command: C,
  value: unknown,
): PdfResult<C> {
  const object = record(value);
  switch (command.operation) {
    case "defaultPdfBudget": {
      const maxima: PdfBudget = {
        fileBytes: 67108864,
        objects: 100000,
        objectNumber: 1000000,
        pages: 1024,
        revisions: 128,
        depth: 64,
        streamBytes: 16777216,
        decodedBytes: 67108864,
        steps: 10000000,
        outputBytes: 67108864,
      };
      for (const [key, max] of Object.entries(maxima))
        if (integer(object[key], max) === 0)
          throw new Error("Invalid PDF budget");
      break;
    }
    case "savePdf":
      integer(object.revision);
      if (object.revision !== command.revision)
        throw new Error("PDF save revision changed");
      object.bytes = bytes(object.bytes, 67108864);
      break;
    case "imagePdf":
    case "decodedImagePdf": {
      const width = integer(object.width, 4096),
        height = integer(object.height, 4096);
      if (
        !width ||
        !height ||
        width * height * 4 > 16777216 ||
        !["rgba", "jpeg"].includes(String(object.kind))
      )
        throw new Error("Invalid PDF image");
      const data = bytes(object.bytes, 16777216);
      if (object.kind === "rgba" && data.length !== width * height * 4)
        throw new Error("Invalid PDF image samples");
      object.bytes = data;
      break;
    }
    case "renderPdfPage":
      drawingBatch(value);
      if (object.page !== command.page || object.revision !== command.revision)
        throw new Error("Stale PDF page");
      integer(object.id);
      spans(object.spans, text(object.text, 262144).length);
      bool(object.textComplete);
      bool(object.displayComplete);
      diagnostics(object.diagnostics);
      break;
    case "extractPdfText":
      if (object.page !== command.page || object.revision !== command.revision)
        throw new Error("Stale PDF text");
      spans(object.spans, text(object.text, 262144).length);
      bool(object.complete);
      diagnostics(object.diagnostics);
      break;
    case "searchPdfPage":
      if (object.page !== command.page || object.revision !== command.revision)
        throw new Error("Stale PDF search");
      bool(object.complete);
      diagnostics(object.diagnostics);
      for (const hit of array(object.hits, 10000)) {
        const item = record(hit);
        if (integer(item.start, 262144) >= integer(item.end, 262144))
          throw new Error("Invalid PDF search range");
        for (const points of array(item.quads, 1048576)) quad(points);
      }
      break;
    case "hitTestPdf":
    case "selectPdf":
      if (object.layoutId !== command.layoutId)
        throw new Error("Stale PDF geometry");
      integer(object.revision);
      text(object.page, 256);
      if (command.operation === "selectPdf") {
        integer(object.anchor, 262144);
        integer(object.focus, 262144);
        for (const points of array(object.quads, 1048576)) quad(points);
      } else integer(object.offset, 262144);
      break;
    case "selectedPdfText":
      text(object.text, 262144);
      break;
    default:
      query(value);
  }
  return value as PdfResult<C>;
}

/** PDF input and edits share one source object graph and one bounded history. */
export class PdfSession extends WasmSession {
  defaultPdfBudget(): PdfBudget {
    return this.execute({ operation: "defaultPdfBudget" });
  }
  execute<C extends PdfCommand>(command: C): PdfResult<C> {
    let value: unknown;
    if (
      command.operation === "openPdf" ||
      command.operation === "decodedImagePdf"
    ) {
      if (
        command.bytes.length >
        (command.operation === "openPdf" ? command.budget.fileBytes : 16777216)
      )
        throw new Error("PDF input exceeds budget");
      value = this.call({ ...command, bytes: encodeBytes(command.bytes) });
    } else value = this.call(command);
    return pdfResult(command, value);
  }
}
