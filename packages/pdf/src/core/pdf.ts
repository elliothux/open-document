import {
  WasmSession,
  encodeBytes,
  resourceBudget,
} from "@open-document/wasm/abi/session";
import { record } from "@open-document/wasm/abi/validation";
import { drawingBatch } from "@open-document/wasm/abi/drawing";

import type { PdfBudget, PdfCommand, PdfResult } from "./pdf-types.js";
export type * from "./pdf-types.js";

const operations: ReadonlySet<string> = new Set([
  "defaultPdfBudget",
  "defaultPdfOfficeBudget",
  "convertPdfOffice",
  "previewPdfRedaction",
  "exportPdfRedaction",
  "openPdf",
  "createPdf",
  "queryPdf",
  "pdfObjects",
  "addPdfText",
  "setPdfPageNumbers",
  "createPdfField",
  "pdfFieldDesign",
  "updatePdfFieldDesign",
  "renamePdfField",
  "deletePdfField",
  "duplicatePdfField",
  "replacePdfText",
  "addPdfImage",
  "movePdfObject",
  "cropPdfImage",
  "deletePdfObject",
  "selectPdfRange",
  "selectedPdfRange",
  "cropPdfPage",
  "resizePdfPage",
  "pdfNavigation",
  "insertPdfPages",
  "replacePdfPages",
  "insertBlankPdfPage",
  "extractPdfPages",
  "splitPdfFiles",
  "splitPdfPage",
  "splitPdfPageGrid",
  "nupPdfPages",
  "exportPdfText",
  "pdfMetadata",
  "setPdfMetadata",
  "renderPdfPage",
  "releasePdfView",
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
  "markPdfText",
  "addPdfDrawingAnnotation",
  "pdfAnnotation",
  "pdfAnnotationThread",
  "editPdfAnnotation",
  "replyPdfAnnotation",
  "deletePdfAnnotationThread",
  "addPdfInkAnnotation",
  "addPdfStampAnnotation",
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
function bounded(value: unknown, min: number, max: number): number {
  if (
    typeof value !== "number" ||
    !Number.isFinite(value) ||
    value < min ||
    value > max
  )
    throw new Error("Invalid PDF number");
  return value;
}
function placement(value: unknown): void {
  const item = record(value);
  for (const key of ["x", "y", "rotation"]) bounded(item[key], -14400, 14400);
  for (const key of ["width", "height"])
    if (!bounded(item[key], 0, 14400)) throw new Error("Invalid PDF placement");
}
function rgb(value: unknown, empty = false): void {
  const color = text(value, 6);
  if ((!empty || color !== "") && !/^[0-9a-fA-F]{6}$/.test(color))
    throw new Error("Invalid PDF color");
}
function fieldDesign(value: unknown): void {
  const spec = record(value);
  for (const key of ["name", "tooltip"]) text(spec[key]);
  if (
    !["text", "checkbox", "radio", "choice", "list"].includes(String(spec.kind))
  )
    throw new Error("Invalid field design kind");
  for (const key of ["readOnly", "required", "multiline", "multiSelect"])
    bool(spec[key]);
  placement(spec.placement);
  text(spec.font, 256);
  bounded(spec.size, 0, 14400);
  bounded(spec.border, 0, 100);
  rgb(spec.color);
  rgb(spec.background, true);
  integer(spec.maxLength, 32767);
  for (const entry of array(spec.options, 4096)) {
    const option = record(entry);
    text(option.value);
    text(option.label);
  }
  for (const key of ["value", "defaultValue"]) {
    if (spec.kind === "checkbox") bool(spec[key]);
    else if (spec.kind === "list")
      for (const value of array(spec[key], 4096)) text(value);
    else text(spec[key]);
  }
}
function annotationStyle(value: unknown): void {
  const style = record(value);
  placement(style.placement);
  rgb(style.color);
  bounded(style.opacity, 0, 1);
  bounded(style.border, 0, 100);
  text(style.author);
  text(style.text);
}
function annotationPoints(value: unknown): void {
  const points = array(value, 32768);
  if (points.length % 2) throw new Error("Invalid annotation point pairs");
  for (const point of points) bounded(point, -14400, 14400);
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
    if (
      !["text", "checkbox", "radio", "choice", "list", "unsupported"].includes(
        String(field.kind),
      )
    )
      throw new Error("Invalid PDF field kind");
    if (["text", "radio", "choice"].includes(String(field.kind)))
      text(field.value);
    else if (field.kind === "checkbox") bool(field.value);
    else if (field.kind === "list") {
      for (const item of array(field.value, 4096)) text(item);
    } else if (field.value !== null)
      throw new Error("Invalid protected PDF field");
    bool(field.multiline);
    bool(field.multiSelect);
    for (const entry of array(field.options, 4096)) {
      const option = record(entry);
      text(option.value);
      text(option.label);
    }
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
    case "defaultPdfOfficeBudget":
      resourceBudget(value);
      break;
    case "convertPdfOffice": {
      if (
        integer(object.revision) !== command.revision ||
        object.format !== command.format
      )
        throw new Error("Stale PDF conversion");
      if (
        ![
          "success",
          "completed-with-loss",
          "needs-acceptance",
          "failed",
        ].includes(String(object.status))
      )
        throw new Error("Invalid PDF conversion status");
      diagnostics(object.warnings);
      text(object.reason);
      for (const entry of array(object.pages, 1024)) {
        const item = record(entry);
        text(item.source, 256);
        integer(item.target, 1048576);
      }
      const completed =
        object.status === "success" || object.status === "completed-with-loss";
      if (completed) {
        if (object.bytes === null) throw new Error("Missing conversion output");
        object.bytes = bytes(
          object.bytes,
          Math.min(67108864, command.budget.outputBytes),
        );
      } else if (object.bytes !== null)
        throw new Error("Unaccepted conversion returned bytes");
      break;
    }
    case "previewPdfRedaction":
      if (integer(object.revision) !== command.revision)
        throw new Error("Stale PDF redaction preview");
      diagnostics(object.warnings);
      text(object.readOnlyReason);
      for (const key of ["regions", "affected"])
        for (const entry of array(object[key], 1048576)) {
          const item = record(entry);
          text(item.page, 256);
          for (const axis of ["x", "y"]) bounded(item[axis], -1e9, 1e9);
          for (const axis of ["width", "height"]) bounded(item[axis], 0, 1e9);
          if (key === "affected") text(item.kind, 256);
        }
      break;
    case "exportPdfRedaction":
      if (integer(object.revision) !== command.revision)
        throw new Error("Stale PDF redaction output");
      diagnostics(object.warnings);
      object.bytes = bytes(object.bytes, 67108864);
      break;
    case "pdfAnnotation":
      if (
        integer(object.revision) !== command.revision ||
        text(object.page, 256) !== command.page ||
        text(object.annotation, 256) !== command.annotation
      )
        throw new Error("Stale PDF annotation");
      text(object.kind, 256);
      annotationStyle(object.style);
      annotationPoints(object.points);
      for (const path of array(object.strokes, 4096)) annotationPoints(path);
      bool(object.arrow);
      bool(object.signature);
      text(object.replyTo, 256);
      break;
    case "pdfAnnotationThread":
      if (integer(object.revision) !== command.revision)
        throw new Error("Stale PDF annotation thread");
      for (const entry of array(object.entries, 4096)) {
        const item = record(entry);
        for (const key of ["id", "page", "parent"]) text(item[key], 256);
        text(item.text);
        text(item.author);
      }
      break;
    case "pdfFieldDesign": {
      if (
        integer(object.revision) !== command.revision ||
        text(object.field, 256) !== command.field
      )
        throw new Error("Stale field design");
      const reason = text(object.readOnlyReason);
      if (object.spec === null) {
        if (!reason) throw new Error("Missing field design");
      } else fieldDesign(object.spec);
      const ids = new Set<string>();
      for (const entry of array(object.widgets, 4096)) {
        const widget = record(entry),
          id = text(widget.id, 256);
        if (!id || ids.has(id))
          throw new Error("Invalid field widget identity");
        ids.add(id);
        text(widget.page, 256);
        placement(widget.placement);
        bounded(widget.border, 0, 100);
        rgb(widget.borderColor, true);
        rgb(widget.background, true);
        text(widget.exportValue);
      }
      break;
    }
    case "pdfObjects":
      if (
        integer(object.revision) !== command.revision ||
        text(object.page, 256) !== command.page
      )
        throw new Error("Stale PDF objects");
      for (const entry of array(object.objects, 4096)) {
        const item = record(entry);
        bool(item.foreground);
        text(item.id, 4096);
        if (!["text", "image", "unsupported"].includes(String(item.kind)))
          throw new Error("Invalid PDF object kind");
        const placement = record(item.placement);
        for (const key of ["x", "y", "width", "height", "rotation"]) {
          const coordinate = placement[key];
          if (
            typeof coordinate !== "number" ||
            !Number.isFinite(coordinate) ||
            Math.abs(coordinate) > 14400
          )
            throw new Error("Invalid PDF placement");
        }
        text(item.text, 262144);
        text(item.font, 256);
        text(item.color, 6);
        text(item.role, 64);
        text(item.readOnlyReason);
        if (
          typeof item.size !== "number" ||
          !Number.isFinite(item.size) ||
          item.size < 0 ||
          item.size > 14400
        )
          throw new Error("Invalid PDF font size");
      }
      break;
    case "selectPdfRange":
    case "selectedPdfRange":
      if (integer(object.revision) !== command.revision)
        throw new Error("Stale PDF range");
      text(object.text, 1048576);
      for (const entry of array(object.pages, 1024)) {
        const page = record(entry);
        text(page.page, 256);
        if (integer(page.start, 262144) > integer(page.end, 262144))
          throw new Error("Invalid PDF range");
        for (const points of array(page.quads, 1048576)) quad(points);
      }
      break;
    case "pdfNavigation": {
      integer(object.revision);
      for (const [key, limit] of [
        ["outlines", 1024],
        ["links", 4096],
      ] as const) {
        for (const entry of array(object[key], limit)) {
          const item = record(entry);
          text(item.id, 256);
          if (key === "outlines") {
            text(item.title);
            integer(item.level, 64);
          } else {
            text(item.page, 256);
            for (const field of ["x", "y", "width", "height"])
              if (
                typeof item[field] !== "number" ||
                !Number.isFinite(item[field]) ||
                Math.abs(item[field]) > 1e9
              )
                throw new Error("Invalid PDF link geometry");
          }
          const target = record(item.target);
          if (!["page", "uri", "blocked"].includes(String(target.kind)))
            throw new Error("Invalid PDF destination");
          text(target.page, 256);
          text(target.uri, 2048);
          text(target.reason);
        }
      }
      break;
    }
    case "pdfMetadata": {
      integer(object.revision);
      text(object.readOnlyReason);
      const fields = record(object.fields);
      for (const key of ["Title", "Author", "Subject", "Keywords"])
        text(fields[key]);
      break;
    }
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
    case "splitPdfFiles": {
      if (object.revision !== command.revision)
        throw new Error("Stale PDF split output");
      let remaining = 67108864;
      const names = new Set<string>();
      for (const entry of array(object.files, 1024)) {
        const file = record(entry),
          name = text(file.name, 64);
        if (!/^part-[0-9]+\.pdf$/.test(name) || names.has(name))
          throw new Error("Invalid PDF output name");
        names.add(name);
        const data = bytes(file.bytes, remaining);
        file.bytes = data;
        remaining -= data.length;
      }
      break;
    }
    case "exportPdfText":
      if (object.revision !== command.revision)
        throw new Error("Stale PDF text output");
      diagnostics(object.warnings);
      object.bytes = bytes(object.bytes, 67108864);
      break;
    case "savePdf":
    case "extractPdfPages":
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
  constructor(exports: WebAssembly.Exports, handle: unknown) {
    super(exports, handle, "pdf");
  }

  defaultPdfBudget(): PdfBudget {
    return this.execute({ operation: "defaultPdfBudget" });
  }
  execute<C extends PdfCommand>(command: C): PdfResult<C> {
    let value: unknown;
    if (
      command.operation === "openPdf" ||
      command.operation === "insertPdfPages" ||
      command.operation === "replacePdfPages" ||
      command.operation === "addPdfImage" ||
      command.operation === "addPdfStampAnnotation" ||
      command.operation === "decodedImagePdf"
    ) {
      if (
        command.bytes.length >
        (command.operation === "openPdf"
          ? command.budget.fileBytes
          : command.operation === "insertPdfPages" ||
              command.operation === "replacePdfPages"
            ? 67108864
            : 16777216)
      )
        throw new Error("PDF input exceeds budget");
      value = this.call({ ...command, bytes: encodeBytes(command.bytes) });
    } else value = this.call(command);
    return pdfResult(command, value);
  }
}
