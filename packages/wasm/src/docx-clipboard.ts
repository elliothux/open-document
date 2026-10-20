import { FoundationPageSession } from "./docx-page.js";
import type { DocxSelection } from "./docx-hit.js";
import { editState } from "./docx-format.js";
import { record } from "./validation.js";
import {
  checkDocxTableEdit,
  docxFragmentImages,
  docxTableClipboard,
  type DocxTableClipboard,
} from "./docx-table.js";
export type DocxClipboard = DocxTableClipboard & { kind: "body" | "cells" };
export function docxClipboard(value: unknown): DocxClipboard {
  docxTableClipboard(value);
  const result = record(value);
  if (result.kind !== "body" && result.kind !== "cells")
    throw new Error("Invalid document clipboard kind");
  return value as DocxClipboard;
}
export class FoundationClipboardSession extends FoundationPageSession {
  clipboard(
    revision: number,
    selection: DocxSelection,
    cut = false,
  ): DocxClipboard {
    return docxClipboard(
      this.call({ operation: "docxClipboard", revision, selection, cut }),
    );
  }
  bodyFragmentImages(revision: number, fragment: string) {
    checkDocxTableEdit({ action: "pasteFragment", fragment });
    return docxFragmentImages(
      this.call({ operation: "bodyFragmentImages", revision, fragment }),
      true,
    );
  }
  pasteBodyFragment(
    revision: number,
    selection: DocxSelection,
    fragment: string,
    profile: Record<string, string>,
  ) {
    checkDocxTableEdit({ action: "pasteFragment", fragment });
    return editState(
      this.call({
        operation: "pasteBodyFragment",
        revision,
        selection,
        fragment,
        profile,
      }),
    );
  }
  tableClipboard(
    revision: number,
    selection: DocxSelection,
    cut = false,
  ): DocxTableClipboard {
    return docxTableClipboard(
      this.call({ operation: "tableClipboard", revision, selection, cut }),
    );
  }
  tableFragmentImages(revision: number, fragment: string) {
    checkDocxTableEdit({ action: "pasteFragment", fragment });
    return docxFragmentImages(
      this.call({ operation: "tableFragmentImages", revision, fragment }),
      true,
    );
  }

  /** Plain-text cut protects pictures; use tableClipboard for rich cell cuts. */
  selectedText(
    revision: number,
    selection: DocxSelection,
    cut = false,
  ): string {
    const result = this.call({
      operation: "selectedText",
      revision,
      selection,
      cut,
    });
    if (typeof result !== "string")
      throw new Error("Invalid selection text returned by Wasm");
    return result;
  }
}
