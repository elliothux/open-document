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
        return workbook.open(request.bytes, request.budget, request.date);
      case "createXlsx":
        return workbook.create(request.budget, request.date);
      case "importXlsxDelimited":
        return workbook.importDelimited(
          request.bytes,
          request.delimiter,
          request.budget,
          request.options,
          request.date,
        );
      case "exportXlsxCsv":
        return workbook.exportCsv(request.revision, request.selection);
      case "queryXlsx":
        return workbook.query(request.sheet, request.range);
      case "picturesXlsx":
        return workbook.pictures(
          request.revision,
          request.sheet,
          request.profile,
        );
      case "shapesXlsx":
        return workbook.shapes(
          request.revision,
          request.sheet,
          request.profile,
        );
      case "insertShapeXlsx":
        return workbook.insertShape(
          request.revision,
          request.sheet,
          request.kind,
          request.width,
          request.height,
          request.text,
          request.profile,
        );
      case "setShapeXlsx":
        return workbook.setShape(
          request.revision,
          request.sheet,
          request.objectId,
          request.settings,
          request.profile,
        );
      case "deleteShapeXlsx":
        return workbook.deleteShape(
          request.revision,
          request.sheet,
          request.objectId,
          request.profile,
        );
      case "pictureResourceXlsx":
        return workbook.pictureResource(request.revision, request.bytes);
      case "selectDrawingXlsx":
        return workbook.selectDrawing(
          request.revision,
          request.layout,
          request.objectId,
        );
      case "drawingGestureXlsx":
        return workbook.drawingGesture(
          request.revision,
          request.layout,
          request,
          request.profile,
        );
      case "imageBytesXlsx":
        return workbook.imageBytes(request.revision, request.key);
      case "imageXlsx":
        return workbook.addImage(
          request.revision,
          request.key,
          request.width,
          request.height,
          request.bytes,
        );
      case "insertPictureXlsx":
        return workbook.insertPicture(
          request.revision,
          request.sheet,
          request.width,
          request.height,
          request.bytes,
          request.profile,
          request.name,
          request.description,
        );
      case "setPictureXlsx":
        return workbook.setPicture(
          request.revision,
          request.sheet,
          request.pictureId,
          request.settings,
          request.profile,
        );
      case "deletePictureXlsx":
        return workbook.deletePicture(
          request.revision,
          request.sheet,
          request.pictureId,
          request.profile,
        );
      case "pivotsXlsx":
        return workbook.pivots(request.revision, request.sheet);
      case "pivotPreviewXlsx":
        return workbook.pivotPreview(request.revision, request.settings);
      case "duplicatesXlsx":
        return workbook.duplicates(
          request.revision,
          request.sheet,
          request.settings,
        );
      case "textColumnsXlsx":
        return workbook.textColumns(
          request.revision,
          request.sheet,
          request.settings,
        );
      case "findXlsx":
        return workbook.find(
          request.revision,
          request.sheet,
          request.text,
          request.options,
        );
      case "replaceXlsxMatches":
        return workbook.replaceMatches(
          request.revision,
          request.sheet,
          request.text,
          request.options,
          request.replacement,
          request.index,
        );
      case "selectXlsx":
        return workbook.select(request.revision, request.sheet, request.range);
      case "replaceXlsx":
        return workbook.replace(
          request.revision,
          request.sheet,
          request.range,
          request.values,
          request.literal,
          request.acceptWarnings,
        );
      case "editXlsxSheet":
        return workbook.editSheet(
          request.revision,
          request.sheet,
          request.change,
          request.date,
        );
      case "autoFitXlsx":
        return workbook.autoFit(
          request.revision,
          request.sheet,
          request.first,
          request.last,
          request.axis,
          request.profile,
        );
      case "formatXlsxCells":
        return workbook.formatCells(request.revision, request.patch);
      case "captureXlsxFormat":
        return workbook.captureFormat(request.revision);
      case "applyXlsxFormat":
        return workbook.applyFormat(request.revision, request.format);
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
      case "fillPreviewXlsx":
        return workbook.fillPreview(request.layoutId, request.target);
      case "navigateXlsx":
        return workbook.navigate(
          request.revision,
          request.direction,
          request.extend,
        );
      case "copyXlsx":
        return workbook.copy(request.revision);
      case "captureXlsxCells":
        return workbook.captureCells(request.revision);
      case "pasteXlsxCells":
        return workbook.pasteCells(
          request.revision,
          request.copied,
          request.mode,
          request.transpose,
          request.acceptWarnings,
        );
      case "pasteXlsx":
        return workbook.paste(
          request.revision,
          request.text,
          request.acceptWarnings,
        );
      case "clearXlsx":
        return workbook.clear(request.revision, request.mode);
      case "printXlsx":
        return workbook.printLayout(
          request.revision,
          request.sheet,
          request.options,
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
        case "createXlsx":
        case "importXlsxDelimited":
        case "exportXlsxCsv":
        case "editXlsxSheet":
        case "autoFitXlsx":
        case "formatXlsxCells":
        case "captureXlsxFormat":
        case "applyXlsxFormat":
        case "queryXlsx":
        case "pivotsXlsx":
        case "pivotPreviewXlsx":
        case "duplicatesXlsx":
        case "textColumnsXlsx":
        case "selectXlsx":
        case "replaceXlsx":
        case "findXlsx":
        case "replaceXlsxMatches":
        case "undoXlsx":
        case "redoXlsx":
        case "saveXlsx":
        case "viewportXlsx":
        case "hitXlsx":
        case "selectionXlsx":
        case "fillPreviewXlsx":
        case "navigateXlsx":
        case "copyXlsx":
        case "captureXlsxCells":
        case "pasteXlsxCells":
        case "pasteXlsx":
        case "clearXlsx":
        case "printXlsx":
        case "exportXlsxPdf":
        case "picturesXlsx":
        case "shapesXlsx":
        case "insertShapeXlsx":
        case "setShapeXlsx":
        case "deleteShapeXlsx":
        case "pictureResourceXlsx":
        case "imageBytesXlsx":
        case "imageXlsx":
        case "insertPictureXlsx":
        case "setPictureXlsx":
        case "deletePictureXlsx":
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
        case "docxRuler":
          return foundation.ruler(request.revision);
        case "editDocxRuler":
          return foundation.editRuler(request.source, request.change);
        case "docxThemeColors":
          return foundation.themeColors(request.revision);
        case "docxThemeFonts":
          return foundation.themeFonts(request.revision);
        case "setDocxThemeFonts":
          return foundation.setThemeFonts(
            request.revision,
            request.fonts,
            request.profile,
          );
        case "setDocxThemeColor":
          return foundation.setThemeColor(
            request.revision,
            request.slot,
            request.color,
          );
        case "styleCatalog":
          return foundation.styles(request.revision, request.kind);
        case "pageSetup":
          return foundation.pageSetup(request.revision);
        case "documentProtection":
          return foundation.documentProtection(request.revision);
        case "setDocumentProtection":
          return foundation.setDocumentProtection(
            request.revision,
            request.enabled,
            request.password,
          );
        case "bodyPageField":
          return foundation.bodyPageField(request.revision, request.selection);
        case "editBodyPageField":
          return foundation.editBodyPageField(
            request.revision,
            request.selection,
            request.field,
            request.profile,
          );
        case "updateBodyPageFields":
          return foundation.updateBodyPageFields(
            request.revision,
            request.profile,
          );
        case "insertBodyPageField":
          return foundation.insertBodyPageField(
            request.revision,
            request.field,
            request.profile,
          );
        case "setPageColumns":
          return foundation.setPageColumns(
            request.revision,
            request.columns,
            request.profile,
          );
        case "setRunningOptions":
          return foundation.setRunningOptions(
            request.revision,
            request.first,
            request.even,
            request.profile,
          );
        case "runningArea":
          return foundation.runningArea(
            request.revision,
            request.kind,
            request.variant,
          );
        case "unlinkRunningArea":
          return foundation.unlinkRunningArea(
            request.revision,
            request.kind,
            request.variant,
            request.profile,
          );
        case "setRunningArea":
          return foundation.setRunningArea(
            request.revision,
            request.kind,
            request.variant,
            request.content,
            request.distance,
            request.profile,
          );
        case "setPageBackground":
          return foundation.setPageBackground(request.revision, request.color);
        case "setCoverPage":
          return foundation.setCoverPage(
            request.revision,
            request.cover,
            request.profile,
          );
        case "setPageBorders":
          return foundation.setPageBorders(request.revision, request.borders);
        case "docxPictures":
          return foundation.pictures(request.revision);
        case "docxShapes":
          return foundation.shapes(request.revision);
        case "editDocxShape":
          return foundation.editShape(
            request.revision,
            request.shape,
            request.profile,
          );
        case "docxDrawingGesture":
          return foundation.drawingGesture(
            request.revision,
            request.change,
            request.profile,
          );
        case "editDocxPicture":
          return foundation.editPicture(
            request.revision,
            request.picture,
            request.profile,
          );
        case "setPageSetup":
          return foundation.setPageSetup(request.revision, request.page);
        case "setPageNumbering":
          return foundation.setPageNumbering(
            request.revision,
            request.numbering,
            request.profile,
          );
        case "insertDocxTable":
          return foundation.insertTable(
            request.revision,
            request.selection,
            request.rows,
            request.columns,
            request.profile,
          );
        case "editDocxTable":
          return foundation.editTable(
            request.revision,
            request.selection,
            request.change,
            request.profile,
          );
        case "setDefaultTabStop":
          return foundation.setDefaultTabStop(
            request.revision,
            request.interval,
          );
        case "listCatalog":
          return foundation.lists(request.revision);
        case "editList":
          return foundation.editList(
            request.revision,
            request.selection,
            request.change,
          );
        case "updateListLevel":
          return foundation.updateListLevel(
            request.revision,
            request.listId,
            request.level,
            request.definition,
          );
        case "createStyle":
          return foundation.createStyle(request.revision, request.style);
        case "deleteStyle":
          return foundation.deleteStyle(
            request.revision,
            request.key,
            request.replacement,
          );
        case "updateStyle":
          return foundation.updateStyle(
            request.revision,
            request.key,
            request.format,
          );
        case "captureFormat":
          return foundation.captureFormat(request.revision, request.selection);
        case "applyFormat":
          return foundation.applyFormat(
            request.revision,
            request.selection,
            request.format,
          );
        case "setCharacterFormat":
          return foundation.setCharacterFormat(
            request.revision,
            request.selection,
            request.format,
          );
        case "setHyperlink":
          return foundation.setHyperlink(
            request.revision,
            request.selection,
            request.target,
            request.text,
          );
        case "setParagraphFormat":
          return foundation.setParagraphFormat(
            request.revision,
            request.selection,
            request.format,
          );
        case "query":
          return foundation.query();
        case "docxOverview":
          return foundation.overview(request.revision);
        case "editBookmark":
          return foundation.editBookmark(request.revision, request.change);
        case "docxComments":
          return foundation.comments(request.revision);
        case "docxRevisions":
          return foundation.revisions(request.revision);
        case "docxRevisionGeometry":
          return foundation.revisionGeometry(
            request.revision,
            request.layoutId,
            request.revisionId,
          );
        case "resolveDocxRevisions":
          return foundation.resolveRevisions(request.revision, request.change);
        case "navigateComment":
          return foundation.navigateComment(
            request.revision,
            request.direction,
          );
        case "editDocxComment":
          return foundation.editComment(request.revision, request.change);
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
        case "enterDocx":
          return foundation.enterDocx(request.revision);
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
          return foundation.selectedText(
            request.revision,
            request.selection,
            request.cut,
          );
        case "tableClipboard":
          return foundation.tableClipboard(
            request.revision,
            request.selection,
            request.cut,
          );
        case "docxClipboard":
          return foundation.clipboard(
            request.revision,
            request.selection,
            request.cut,
          );
        case "bodyFragmentImages":
          return foundation.bodyFragmentImages(
            request.revision,
            request.fragment,
          );
        case "markupImages":
          return foundation.markupImages(
            request.revision,
            request.kind,
            request.input,
            request.mode,
          );
        case "pasteBodyFragment":
          return foundation.pasteBodyFragment(
            request.revision,
            request.selection,
            request.fragment,
            request.profile,
          );
        case "pasteMarkdown":
          return foundation.pasteMarkdown(
            request.revision,
            request.selection,
            request.markdown,
            request.profile,
            request.mode,
          );
        case "pasteHtml":
          return foundation.pasteHtml(
            request.revision,
            request.selection,
            request.html,
            request.profile,
            request.mode,
          );
        case "tableFragmentImages":
          return foundation.tableFragmentImages(
            request.revision,
            request.fragment,
          );
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
        case "exportDocxMarkup":
          return foundation.exportMarkup(
            request.revision,
            request.format,
            request.outputBytes,
          );
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
