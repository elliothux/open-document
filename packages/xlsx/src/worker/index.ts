import { serveWorker } from "@open-document/web-core/worker";
import { instantiateXlsx } from "../core/engine.js";
import type { XlsxSession } from "../core/index.js";
import type { Operation } from "./protocol.js";
import {
  isXlsxDrawingRequest,
  drawingOperation,
} from "./worker-xlsx-drawings.js";
import {
  isXlsxCommentsRequest,
  commentsOperation,
} from "./worker-xlsx-comments.js";
let workbook: XlsxSession | undefined;
async function dispatch(request: Operation): Promise<unknown> {
  if (request.operation === "initialize") {
    if (workbook) throw new Error("Session is already open");
    workbook = await instantiateXlsx(request.module);
    return null;
  }
  if (!workbook) throw new Error("Session is not open");
  if (isXlsxDrawingRequest(request)) return drawingOperation(workbook, request);
  if (isXlsxCommentsRequest(request))
    return commentsOperation(workbook, request);
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
    case "consolidationXlsx":
      return workbook.consolidation(
        request.revision,
        request.sheet,
        request.settings,
      );
    case "subtotalsXlsx":
      return workbook.subtotals(
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
serveWorker(dispatch);
