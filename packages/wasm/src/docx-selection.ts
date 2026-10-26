import { FoundationInkSession } from "./docx-ink.js";
import { editState, type EditState } from "./docx-format.js";
import {
  docxSelectionGeometry,
  type DocxSelection,
  type DocxSelectionGeometry,
} from "./docx-hit.js";

export class FoundationSelectionSession extends FoundationInkSession {
  selectDocx(revision: number, selection: DocxSelection): EditState {
    return editState(
      this.call({ operation: "selectDocx", revision, selection }),
    );
  }

  /** Selects the body, or the text box containing the current caret. */
  selectAllDocx(revision: number): EditState {
    return editState(this.call({ operation: "selectAllDocx", revision }));
  }

  selectionGeometry(
    layoutId: number,
    selection: DocxSelection,
  ): DocxSelectionGeometry {
    return docxSelectionGeometry(
      this.call({ operation: "selectionGeometry", layoutId, selection }),
    );
  }
}
