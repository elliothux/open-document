import { FoundationPageSession } from "./docx-page.js";
import type { DocxSelection } from "./docx-hit.js";
import { editState } from "./docx-format.js";
import { record } from "@open-document/wasm/abi/validation";
import {
  checkDocxTableEdit,
  docxFragmentImages,
  docxTableClipboard,
  type DocxTableClipboard,
} from "./docx-table.js";
export type DocxClipboard = DocxTableClipboard & { kind: "body" | "cells" };
export type DocxPasteMode = "source" | "merge" | "text";
export function checkDocxPasteMode(
  mode: unknown,
): asserts mode is DocxPasteMode {
  if (mode !== "source" && mode !== "merge" && mode !== "text")
    throw new Error("Unknown markup paste mode");
}
export function checkMarkdown(markdown: string): void {
  if (
    typeof markdown !== "string" ||
    !markdown.trim() ||
    markdown.length > 65536
  )
    throw new Error("Markdown requires 1..65536 source units");
}
export function checkHtml(html: string): void {
  if (typeof html !== "string" || !html.trim() || html.length > 65536)
    throw new Error("HTML requires 1..65536 source units");
}
export function docxClipboard(value: unknown): DocxClipboard {
  docxTableClipboard(value);
  const result = record(value);
  if (result.kind !== "body" && result.kind !== "cells")
    throw new Error("Invalid document clipboard kind");
  return value as DocxClipboard;
}
export class FoundationClipboardSession extends FoundationPageSession {
  markupImages(
    revision: number,
    kind: "html" | "markdown",
    input: string,
    mode: DocxPasteMode = "source",
  ) {
    checkDocxPasteMode(mode);
    if (kind === "html") checkHtml(input);
    else if (kind === "markdown") checkMarkdown(input);
    else throw new Error("Unknown markup input format");
    return docxFragmentImages(
      this.call({ operation: "markupImages", revision, kind, input, mode }),
      true,
    );
  }
  pasteHtml(
    revision: number,
    selection: DocxSelection,
    html: string,
    profile: Record<string, string>,
    mode: DocxPasteMode = "source",
  ) {
    checkHtml(html);
    checkDocxPasteMode(mode);
    return editState(
      this.call({
        operation: "pasteHtml",
        revision,
        selection,
        html,
        profile,
        mode,
      }),
    );
  }
  pasteMarkdown(
    revision: number,
    selection: DocxSelection,
    markdown: string,
    profile: Record<string, string>,
    mode: DocxPasteMode = "source",
  ) {
    checkMarkdown(markdown);
    checkDocxPasteMode(mode);
    return editState(
      this.call({
        operation: "pasteMarkdown",
        revision,
        selection,
        markdown,
        profile,
        mode,
      }),
    );
  }
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
