import { loadEngine, type TextSession } from "@open-document/wasm/engine";
import type { FoundationSession } from "@open-document/wasm/foundation";
import type { XlsxSession } from "@open-document/wasm/xlsx";
import { isPptxCommand, type PptxSession } from "@open-document/wasm/pptx";
import { isPdfCommand, type PdfSession } from "@open-document/wasm/pdf";
import type { Request, Response } from "./protocol";

let text: TextSession | undefined;
let foundation: FoundationSession | undefined;
let workbook: XlsxSession | undefined;
let presentation: PptxSession | undefined;
let pdf: PdfSession | undefined;
let busy = false;

async function dispatch(request: Request): Promise<unknown> {
  if (
    request.operation === "open" ||
    request.operation === "openFoundation" ||
    request.operation === "openSpreadsheet" ||
    request.operation === "openPresentation" ||
    request.operation === "openPdfWorker"
  ) {
    if (text || foundation || workbook || presentation || pdf)
      throw new Error("Session is already open");
    const engine = await loadEngine(request.wasm);
    if (request.operation === "openPdfWorker") {
      pdf = engine.openPdf();
      return null;
    }
    if (request.operation === "openPresentation") {
      presentation = engine.openPptx();
      return null;
    }
    if (request.operation === "open") {
      text = engine.openText(request.text);
      return text.read();
    }
    if (request.operation === "openSpreadsheet") {
      workbook = engine.openXlsx();
      return null;
    }
    foundation = engine.openFoundation();
    return null;
  }
  if (pdf) {
    if (request.operation === "font") {
      pdf.addFont(request.bytes, request.identity);
      return null;
    }
    if (isPdfCommand(request)) return pdf.execute(request);
    throw new Error("Operation is unavailable in a PDF session");
  }
  if (isPdfCommand(request)) throw new Error("Open a PDF client first");
  if (presentation) {
    if (request.operation === "budget") return presentation.defaultBudget();
    if (request.operation === "font") {
      presentation.addFont(request.bytes, request.identity);
      return null;
    }
    if (isPptxCommand(request)) return presentation.execute(request);
    throw new Error("Operation is unavailable in a PPTX session");
  }
  if (workbook) {
    switch (request.operation) {
      case "budget":
        return workbook.defaultBudget();
      case "font":
        workbook.addFont(request.bytes, request.identity);
        return null;
      case "openXlsx":
        return workbook.open(request.bytes, request.budget);
      case "queryXlsx":
        return workbook.query(request.sheet, request.range);
      case "selectXlsx":
        return workbook.select(request.revision, request.sheet, request.range);
      case "replaceXlsx":
        return workbook.replace(
          request.revision,
          request.sheet,
          request.range,
          request.values,
          request.literal,
        );
      case "undoXlsx":
        return workbook.undo(request.revision);
      case "redoXlsx":
        return workbook.redo(request.revision);
      case "saveXlsx":
        return workbook.save();
      case "viewportXlsx":
        return workbook.viewport(request);
      case "hitXlsx":
        return workbook.hit(request.layoutId, request.x, request.y);
      case "selectionXlsx":
        return workbook.selectionGeometry(request.layoutId);
      case "navigateXlsx":
        return workbook.navigate(
          request.revision,
          request.direction,
          request.extend,
        );
      case "copyXlsx":
        return workbook.copy(request.revision);
      case "pasteXlsx":
        return workbook.paste(request.revision, request.text);
      case "clearXlsx":
        return workbook.clear(request.revision);
      case "printXlsx":
        return workbook.printLayout(
          request.revision,
          request.sheet,
          request,
          request.profile,
        );
      case "exportXlsxPdf":
        return workbook.exportPdf(request.layoutId, request.outputBytes);
      default:
        throw new Error("Operation is unavailable in an XLSX session");
    }
  }
  switch (request.operation) {
    case "read":
    case "undo":
    case "replace":
      if (!text) throw new Error("Text session is not open");
      if (request.operation === "undo") text.undo();
      if (request.operation === "replace")
        text.replace(request.start, request.end, request.text);
      return text.read();
    default:
      if (!foundation) throw new Error("Foundation session is not open");
      switch (request.operation) {
        case "openXlsx":
        case "queryXlsx":
        case "selectXlsx":
        case "replaceXlsx":
        case "undoXlsx":
        case "redoXlsx":
        case "saveXlsx":
        case "viewportXlsx":
        case "hitXlsx":
        case "selectionXlsx":
        case "navigateXlsx":
        case "copyXlsx":
        case "pasteXlsx":
        case "clearXlsx":
        case "printXlsx":
        case "exportXlsxPdf":
          throw new Error("Open an XLSX client first");
        case "budget":
          return foundation.defaultBudget();
        case "font":
          foundation.addFont(request.bytes, request.identity);
          return null;
        case "shape":
          return foundation.shape(request.text, request.size, request.language);
        case "openDocx":
          return foundation.openDocx(request.bytes, request.budget);
        case "createDocx":
          return foundation.createDocx(request.budget);
        case "queryFormatting":
          return foundation.queryFormatting(
            request.revision,
            request.selection,
          );
        case "setCharacterFormat":
          return foundation.setCharacterFormat(
            request.revision,
            request.selection,
            request.format,
          );
        case "setParagraphFormat":
          return foundation.setParagraphFormat(
            request.revision,
            request.selection,
            request.format,
          );
        case "query":
          return foundation.query();
        case "findDocx":
          return foundation.findDocx(
            request.revision,
            request.text,
            request.options,
          );
        case "replaceDocxMatches":
          return foundation.replaceDocxMatches(
            request.revision,
            request.matches,
            request.text,
          );
        case "tabDocx":
          return foundation.tabDocx(request.revision, request.backward);
        case "editState":
          return foundation.editState();
        case "beginComposition":
          return foundation.beginComposition(request.revision);
        case "updateComposition":
          return foundation.updateComposition(
            request.revision,
            request.compositionId,
            request.text,
          );
        case "commitComposition":
          return foundation.commitComposition(
            request.revision,
            request.compositionId,
            request.text,
          );
        case "cancelComposition":
          return foundation.cancelComposition(
            request.revision,
            request.compositionId,
          );
        case "selectDocx":
          return foundation.selectDocx(request.revision, request.selection);
        case "selectedText":
          return foundation.selectedText(request.revision, request.selection);
        case "replaceRange":
          return foundation.replaceRange(
            request.revision,
            request.selection,
            request.text,
            request.inputGroup,
          );
        case "undoDocx":
          return foundation.undoDocx(request.revision);
        case "deleteDocx":
          return foundation.deleteDocx(request.revision, request.direction);
        case "redoDocx":
          return foundation.redoDocx(request.revision);
        case "replaceNode":
          return foundation.replaceNode(
            request.node,
            request.revision,
            request.text,
          );
        case "saveDocx":
          return foundation.saveDocx();
        case "flow":
          return foundation.flow();
        case "layout":
          return foundation.layout(request.profile);
        case "hitTest":
          return foundation.hitTest(
            request.layoutId,
            request.page,
            request.x,
            request.y,
          );
        case "caret":
          return foundation.caret(request.layoutId, request.position);
        case "navigateDocx":
          return foundation.navigateDocx(
            request.revision,
            request.layoutId,
            request.direction,
            request.extend,
          );
        case "selectionGeometry":
          return foundation.selectionGeometry(
            request.layoutId,
            request.selection,
          );
        case "exportPdf":
          return foundation.exportPdf(request.outputBytes, request.layoutId);
        case "imageBytes":
          return foundation.imageBytes(request.key);
        case "image":
          return foundation.addImage(
            request.key,
            request.width,
            request.height,
            request.bytes,
          );
      }
  }
}

globalThis.onmessage = async (event: MessageEvent<Request>) => {
  const request = event.data;
  let response: Response;
  if (busy) {
    globalThis.postMessage({
      id: request.id,
      ok: false,
      error: "Await the previous operation",
    });
    return;
  }
  busy = true;
  try {
    response = { id: request.id, ok: true, value: await dispatch(request) };
  } catch (error) {
    response = {
      id: request.id,
      ok: false,
      error: error instanceof Error ? error.message : String(error),
      ...(error instanceof Error &&
      error.name === "DocumentError" &&
      "code" in error &&
      typeof error.code === "string" &&
      "part" in error &&
      typeof error.part === "string" &&
      "offset" in error &&
      typeof error.offset === "number"
        ? { code: error.code, part: error.part, offset: error.offset }
        : {}),
    };
  } finally {
    busy = false;
  }
  globalThis.postMessage(response);
};
