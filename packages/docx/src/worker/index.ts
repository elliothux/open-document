import { serveWorker } from "@open-document/web-core/worker";
import { instantiateDocx } from "../core/engine.js";
import type { FoundationSession } from "../core/index.js";
import type { Operation } from "./protocol.js";
import { mathOperation } from "./worker-math.js";
import { inkOperation } from "./worker-docx-ink.js";
import { reviewOperation } from "./worker-docx-review.js";
import { noteOperation } from "./worker-docx-notes.js";
import { selectionOperation } from "./worker-docx-selection.js";
let foundation: FoundationSession | undefined;
async function dispatch(request: Operation): Promise<unknown> {
  if (request.operation === "initialize") {
    if (foundation) throw new Error("Session is already open");
    foundation = await instantiateDocx(request.module);
    return null;
  }
  if (!foundation) throw new Error("Session is not open");
  switch (request.operation) {
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
      return foundation.queryFormatting(request.revision, request.selection);
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
    case "noteNumbering":
    case "setNoteNumbering":
    case "setEndnotePosition":
    case "insertDocxNote":
    case "removeDocxNote":
    case "editDocxNote":
      return noteOperation(foundation, request);
    case "editBodyPageField":
      return foundation.editBodyPageField(
        request.revision,
        request.selection,
        request.field,
        request.profile,
      );
    case "updateBodyPageFields":
      return foundation.updateBodyPageFields(request.revision, request.profile);
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
    case "editDocxBibliography":
      return foundation.editBibliography(
        request.revision,
        request.change,
        request.profile,
      );
    case "editDocxCitation":
      return foundation.editCitation(
        request.revision,
        request.change,
        request.profile,
      );
    case "docxSources":
      return foundation.sources(request.revision);
    case "editDocxSource":
      return foundation.editSource(request.revision, request.change);
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
    case "docxInk":
      return inkOperation(foundation, request);
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
      return foundation.setDefaultTabStop(request.revision, request.interval);
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
    case "docxRevisionGeometry":
    case "resolveDocxRevisions":
    case "docxTracking":
    case "setDocxTracking":
      return reviewOperation(foundation, request);
    case "navigateComment":
      return foundation.navigateComment(request.revision, request.direction);
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
    case "selectAllDocx":
    case "selectedText":
      return selectionOperation(foundation, request);
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
      return foundation.bodyFragmentImages(request.revision, request.fragment);
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
      return foundation.tableFragmentImages(request.revision, request.fragment);
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
      return foundation.selectionGeometry(request.layoutId, request.selection);
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
serveWorker(dispatch);
