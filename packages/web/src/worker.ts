import {
  isXlsxDrawingRequest,
  drawingOperation,
} from "./worker-xlsx-drawings.js";
import { loadEngine, type TextSession } from "@open-document/wasm/engine";
import type { FoundationSession } from "@open-document/wasm/foundation";
import type { XlsxSession } from "@open-document/wasm/xlsx";
import { isPptxCommand, type PptxSession } from "@open-document/wasm/pptx";
import { isPdfCommand, type PdfSession } from "@open-document/wasm/pdf";
import { errorResponse, type Request, type Response } from "./protocol";
import { mathOperation } from "./worker-math.js";
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
  if (isXlsxDrawingRequest(request)) return drawingOperation(workbook, request);
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
      case "pivotsXlsx":
        return workbook.pivots(request.revision, request.sheet);
      case "slicersXlsx":
        return workbook.slicers(request.revision, request.sheet);
      case "timelinesXlsx":
        return workbook.timelines(request.revision, request.sheet);
      case "pivotPreviewXlsx":
        return workbook.pivotPreview(
          request.revision,
          request.settings,
          request.part,
        );
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
        case "slicersXlsx":
        case "timelinesXlsx":
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
          return foundation.pageSetup(request.revision, request.section);
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
        case "docxNotes":
          return foundation.notes(request.revision);
        case "insertDocxNote":
          return foundation.insertNote(
            request.revision,
            request.note,
            request.profile,
          );
        case "removeDocxNote":
          return foundation.removeNote(
            request.revision,
            request.note,
            request.profile,
          );
        case "editDocxNote":
          return foundation.editNote(
            request.revision,
            request.note,
            request.profile,
          );
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
        case "insertSectionBreak":
          return foundation.insertSectionBreak(
            request.revision,
            request.kind,
            request.profile,
          );
        case "insertDocxCaption":
          return foundation.insertCaption(
            request.revision,
            request.caption,
            request.profile,
          );
        case "docxTableOfContents":
          return foundation.tableOfContents(request.revision);
        case "docxIndexes":
          return foundation.indexes(request.revision);
        case "editDocxIndex":
          return foundation.editIndex(
            request.revision,
            request.change,
            request.profile,
          );
        case "editDocxTableOfContents":
          return foundation.editTableOfContents(
            request.revision,
            request.change,
            request.profile,
          );
        case "setPageColumns":
          return foundation.setPageColumns(
            request.revision,
            request.section,
            request.columns,
            request.profile,
          );
        case "setRunningOptions":
          return foundation.setRunningOptions(
            request.revision,
            request.section,
            request.first,
            request.even,
            request.profile,
          );
        case "runningArea":
          return foundation.runningArea(
            request.revision,
            request.section,
            request.kind,
            request.variant,
          );
        case "setRunningLink":
          return foundation.setRunningLink(
            request.revision,
            request.section,
            request.kind,
            request.variant,
            request.linked,
            request.profile,
          );
        case "setRunningArea":
          return foundation.setRunningArea(
            request.revision,
            request.section,
            request.kind,
            request.variant,
            request.content,
            request.distance,
            request.profile,
          );
        case "setPageBackground":
          return foundation.setPageBackground(request.revision, request.color);
        case "watermark":
          return foundation.watermark(request.revision, request.section);
        case "setWatermark":
          return foundation.setWatermark(
            request.revision,
            request.section,
            request.value,
            request.profile,
          );
        case "setCoverPage":
          return foundation.setCoverPage(
            request.revision,
            request.cover,
            request.profile,
          );
        case "setPageBorders":
          return foundation.setPageBorders(
            request.revision,
            request.section,
            request.borders,
          );
        case "docxPictures":
          return foundation.pictures(request.revision);
        case "docxCharts":
          return foundation.charts(request.revision);
        case "editDocxChart":
          return foundation.editChart(
            request.revision,
            request.chart,
            request.profile,
          );
        case "docxShapes":
          return foundation.shapes(request.revision);
        case "docxMathFractions":
        case "docxMathScripts":
        case "docxMathExpressions":
        case "editDocxMath":
        case "editDocxMathScript":
        case "editDocxMathFraction":
          return mathOperation(foundation, request);
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
            request.section,
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
            request.profile,
          );
        case "setCharacterFormat":
          return foundation.setCharacterFormat(
            request.revision,
            request.selection,
            request.format,
            request.profile,
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
            request.profile,
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
    response = errorResponse(request.id, error);
  } finally {
    busy = false;
  }
  globalThis.postMessage(response);
};
