import {
  checkDocxThemeFonts,
  checkDocxThemeColor,
  checkDocxTableSize,
  checkDocxTableEdit,
  checkDocxHyperlink,
  copiedFormat,
  checkStyleUpdate,
  checkStyleCreation,
  checkDefaultTabStop,
  checkDocxPictureEdit,
  checkDocxDrawingGesture,
  checkFormatPatch,
  checkListEdit,
  checkListLevelUpdate,
  checkFindOptions,
} from "./foundation.js";
import {
  checkDocxBibliographyEdit,
  checkDocxCitationEdit,
  checkDocxSourceEdit,
} from "./foundation.js";
import { checkDocxIndexEdit } from "./foundation.js";
import { docxRuler, checkDocxRulerEdit } from "./foundation.js";
import {
  checkPageSetup,
  checkPageSection,
  checkDocxCoverPage,
  checkDocxWatermark,
  checkDocxCaption,
  checkSectionBreak,
  checkPageBackground,
  checkPageBorders,
  checkPageNumbering,
  checkDocxColumns,
  checkRunningArea,
  checkRunningKind,
  checkRunningVariant,
  checkRunningOptions,
  checkBodyField,
  checkDocxProtection,
} from "./foundation.js";

import { checkDocxTocEdit } from "./foundation.js";
import { checkMarkdown, checkHtml, checkDocxPasteMode } from "./foundation.js";
import { checkDocxRevisionIdentity } from "./docx-revisions.js";

import {
  checkTrackingAuthor,
  checkInkStroke,
  checkInkPoint,
  checkInkTarget,
  checkDocxChartEdit,
  checkDocxMathEdit,
  checkDocxFractionEdit,
  checkDocxScriptEdit,
  checkDocxShapeEdit,
  checkDocxRevisionEdit,
  checkDocxBookmark,
  checkDocxComment,
  checkNoteNumbering,
  checkEndnotePosition,
  checkDocxNoteEdit,
  checkDocxNoteCreate,
  checkDocxNoteIdentity,
} from "./foundation.js";
import type { DocxCommand } from "./docx-command.js";
import {
  checkByteInput,
  type InputLimits,
} from "@open-document/wasm/abi/session";

export interface DocxInputLimits extends InputLimits {
  readonly exportBytes: number;
  readonly imageBytes: number;
  readonly rgbaBytes: number;
  readonly inkPoints: number;
  readonly markupSourceUnits: number;
  readonly clipboardFragmentUnits: number;
  readonly textCommandUnits: number;
  readonly revisionEntries: number;
}

/** Share core byte ceilings between synchronous sessions and Worker clients. */
export function checkDocxByteInput(
  command: DocxCommand,
  limits: DocxInputLimits,
): void {
  if (command.operation === "openDocx")
    checkByteInput(
      command.bytes,
      Math.min(command.budget.fileBytes, command.budget.retainedBytes),
    );
  else if (command.operation === "rasterHeaderDocx")
    checkByteInput(command.bytes, limits.imageBytes);
  else if (command.operation === "addImage")
    checkByteInput(command.rgba, limits.rgbaBytes);
  else if (command.operation === "editPicture" && "bytes" in command.picture)
    checkByteInput(command.picture.bytes, limits.imageBytes);
  else if (
    command.operation === "setWatermark" &&
    command.value?.kind === "picture" &&
    command.value.image instanceof Uint8Array
  )
    checkByteInput(command.value.image, limits.imageBytes);
}

/** Check untrusted host values before structured cloning; validators remain in their owning domains. */
export function checkDocxInput(
  command: DocxCommand,
  inputLimits: () => DocxInputLimits,
): void {
  switch (command.operation) {
    case "setThemeFonts": {
      const { fonts } = command;

      checkDocxThemeFonts(fonts);
      break;
    }
    case "setThemeColor": {
      const { slot, color } = command;

      checkDocxThemeColor(slot, color);
      break;
    }
    case "editList": {
      const { change } = command;

      checkListEdit(change);
      break;
    }
    case "updateListLevel": {
      const { id, level, definition } = command;

      checkListLevelUpdate(id, level, definition);
      break;
    }
    case "updateStyle": {
      const { format } = command;

      checkStyleUpdate(format);
      break;
    }
    case "createStyle": {
      const { style } = command;

      checkStyleCreation(style);
      break;
    }
    case "drawingGesture": {
      const { change } = command;

      checkDocxDrawingGesture(change);
      break;
    }
    case "editPicture": {
      const { picture } = command;

      checkDocxPictureEdit(picture);
      break;
    }
    case "insertTable": {
      const { rows, columns } = command;

      checkDocxTableSize(rows, columns);
      break;
    }
    case "setDefaultTabStop": {
      const { interval } = command;

      checkDefaultTabStop(interval);
      break;
    }
    case "editTable": {
      const { change } = command;

      checkDocxTableEdit(change, inputLimits);
      break;
    }
    case "applyFormat": {
      const { format } = command;

      copiedFormat(format);
      break;
    }
    case "setCharacterFormat": {
      const { format } = command;

      checkFormatPatch(format);
      break;
    }
    case "setHyperlink": {
      const { target, text } = command;

      checkDocxHyperlink(target, text);
      break;
    }
    case "setParagraphFormat": {
      const { format } = command;

      checkFormatPatch(format, true);
      break;
    }
    case "findDocx": {
      const { options = {} } = command;

      checkFindOptions(options);
      break;
    }
    case "insertSectionBreak": {
      const { kind } = command;

      checkSectionBreak(kind);
      break;
    }
    case "editBibliography": {
      const { change } = command;

      checkDocxBibliographyEdit(change);
      break;
    }
    case "editCitation": {
      const { change } = command;

      checkDocxCitationEdit(change);
      break;
    }
    case "editSource": {
      const { change } = command;

      checkDocxSourceEdit(change);
      break;
    }
    case "editIndex": {
      const { change } = command;

      checkDocxIndexEdit(change);
      break;
    }
    case "editTableOfContents": {
      const { change } = command;

      checkDocxTocEdit(change);
      break;
    }
    case "setDocumentProtection": {
      const { enabled, password } = command;

      checkDocxProtection(enabled, password);
      break;
    }
    case "editBodyPageField": {
      const { field } = command;

      checkBodyField(field);
      break;
    }
    case "insertBodyPageField": {
      const { field } = command;

      checkBodyField(field);
      break;
    }
    case "insertCaption": {
      const { caption } = command;

      checkDocxCaption(caption);
      break;
    }
    case "editRuler": {
      const { source, change } = command;

      docxRuler(source);
      checkDocxRulerEdit(change);
      break;
    }
    case "setPageColumns": {
      const { section, columns } = command;

      checkPageSection(section);
      checkDocxColumns(columns);
      break;
    }
    case "setPageNumbering": {
      const { section, numbering } = command;

      checkPageSection(section);
      checkPageNumbering(numbering);
      break;
    }
    case "setRunningLink": {
      const { section, kind, variant, linked } = command;

      checkPageSection(section);
      if (typeof linked !== "boolean")
        throw new Error("Invalid running link state");
      checkRunningKind(kind);
      checkRunningVariant(variant);
      break;
    }
    case "setRunningOptions": {
      const { section, first, even } = command;

      checkPageSection(section);
      checkRunningOptions(first, even);
      break;
    }
    case "pageSetup": {
      const { section = 0 } = command;

      checkPageSection(section);
      break;
    }
    case "setPageSetup": {
      const { page } = command;

      checkPageSetup(page);
      break;
    }
    case "setPageBackground": {
      const { color } = command;

      checkPageBackground(color);
      break;
    }
    case "watermark": {
      const { section } = command;

      checkPageSection(section);
      break;
    }
    case "setWatermark": {
      const { section, value } = command;

      checkPageSection(section);
      checkDocxWatermark(value);
      break;
    }
    case "setCoverPage": {
      const { cover } = command;

      checkDocxCoverPage(cover);
      break;
    }
    case "setPageBorders": {
      const { section, borders } = command;

      checkPageSection(section);
      checkPageBorders(borders);
      break;
    }
    case "runningArea": {
      const { section, kind, variant } = command;

      checkPageSection(section);
      checkRunningKind(kind);
      checkRunningVariant(variant);
      break;
    }
    case "setRunningArea": {
      const { section, kind, variant, content, distance } = command;

      checkPageSection(section);
      checkRunningArea(kind, variant, content, distance);
      break;
    }
    case "markupImages": {
      const { kind, input, mode = "source" } = command;

      checkDocxPasteMode(mode);
      if (kind === "html") checkHtml(input, inputLimits().markupSourceUnits);
      else if (kind === "markdown")
        checkMarkdown(input, inputLimits().markupSourceUnits);
      else throw new Error("Unknown markup input format");
      break;
    }
    case "bodyFragmentImages": {
      const { fragment } = command;

      checkDocxTableEdit({ action: "pasteFragment", fragment }, inputLimits);
      break;
    }
    case "pasteBodyFragment": {
      const { fragment } = command;

      checkDocxTableEdit({ action: "pasteFragment", fragment }, inputLimits);
      break;
    }
    case "tableFragmentImages": {
      const { fragment } = command;

      checkDocxTableEdit({ action: "pasteFragment", fragment }, inputLimits);
      break;
    }
    case "setTracking": {
      const { author } = command;

      checkTrackingAuthor(author);
      break;
    }
    case "previewInk":
    case "insertInk": {
      const { revision, layoutId, page, stroke } = command;

      checkInkTarget(revision, layoutId, page);
      checkInkStroke(stroke, () => inputLimits().inkPoints);
      break;
    }
    case "eraseInk": {
      const { revision, layoutId, page, x, y } = command;

      checkInkTarget(revision, layoutId, page);
      checkInkPoint(x, y);
      break;
    }
    case "insertNote": {
      const { note } = command;

      checkDocxNoteCreate(note);
      break;
    }
    case "removeNote": {
      const { note } = command;

      checkDocxNoteIdentity(note);
      break;
    }
    case "setNoteNumbering": {
      const { numbering } = command;

      checkNoteNumbering(numbering);
      break;
    }
    case "setEndnotePosition": {
      const { position } = command;

      checkEndnotePosition(position);
      break;
    }
    case "editNote": {
      const { note } = command;

      checkDocxNoteEdit(note);
      break;
    }
    case "editChart": {
      const { chart } = command;

      checkDocxChartEdit(chart);
      break;
    }
    case "editMath": {
      const { math } = command;

      checkDocxMathEdit(math);
      break;
    }
    case "editMathScript": {
      const { script } = command;

      checkDocxScriptEdit(script);
      break;
    }
    case "editMathFraction": {
      const { fraction } = command;

      checkDocxFractionEdit(fraction);
      break;
    }
    case "editShape": {
      const { shape } = command;

      checkDocxShapeEdit(shape);
      break;
    }
    case "revisionGeometry": {
      const { id } = command;

      checkDocxRevisionIdentity(id);
      break;
    }
    case "resolveRevisions": {
      const { change } = command;

      checkDocxRevisionEdit(change, inputLimits().revisionEntries);
      break;
    }
    case "navigateComment": {
      const { direction } = command;

      if (direction !== "previous" && direction !== "next")
        throw new Error("Invalid comment navigation direction");
      break;
    }
    case "editBookmark": {
      const { change } = command;

      checkDocxBookmark(change);
      break;
    }
    case "editComment": {
      const { change } = command;

      checkDocxComment(change);
      break;
    }
  }
}
