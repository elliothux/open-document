import { FoundationPageClient } from "./foundation-page.js";
import {
  docxClipboard,
  docxTableClipboard,
  docxFragmentImages,
  checkDocxTableEdit,
  checkMarkdown,
  checkHtml,
  checkDocxPasteMode,
  editState,
  type DocxTableClipboard,
  type DocxSelection,
  type DocxPasteMode,
} from "@open-document/wasm/foundation";
import {
  prepareDocxFragmentImages,
  prepareDocxImages,
} from "./document-fragment-images.js";
export abstract class FoundationClipboardClient extends FoundationPageClient {
  async markupImages(
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
      await this.connection.request({
        operation: "markupImages",
        revision,
        kind,
        input,
        mode,
      }),
      false,
    );
  }
  async pasteHtml(
    revision: number,
    selection: DocxSelection,
    html: string,
    profile: Record<string, string>,
    mode: DocxPasteMode = "source",
  ) {
    await prepareDocxImages(
      this,
      await this.markupImages(revision, "html", html, mode),
    );
    return editState(
      await this.connection.request({
        operation: "pasteHtml",
        revision,
        selection,
        html,
        profile,
        mode,
      }),
    );
  }
  async pasteMarkdown(
    revision: number,
    selection: DocxSelection,
    markdown: string,
    profile: Record<string, string>,
    mode: DocxPasteMode = "source",
  ) {
    await prepareDocxImages(
      this,
      await this.markupImages(revision, "markdown", markdown, mode),
    );
    return editState(
      await this.connection.request({
        operation: "pasteMarkdown",
        revision,
        selection,
        markdown,
        profile,
        mode,
      }),
    );
  }
  abstract addImage(
    key: string,
    width: number,
    height: number,
    bytes: Uint8Array,
  ): Promise<string>;
  async clipboard(revision: number, selection: DocxSelection, cut = false) {
    return docxClipboard(
      await this.connection.request({
        operation: "docxClipboard",
        revision,
        selection,
        cut,
      }),
    );
  }
  async bodyFragmentImages(revision: number, fragment: string) {
    checkDocxTableEdit({ action: "pasteFragment", fragment });
    return docxFragmentImages(
      await this.connection.request({
        operation: "bodyFragmentImages",
        revision,
        fragment,
      }),
      false,
    );
  }
  async pasteBodyFragment(
    revision: number,
    selection: DocxSelection,
    fragment: string,
    profile: Record<string, string>,
  ) {
    checkDocxTableEdit({ action: "pasteFragment", fragment });
    await prepareDocxFragmentImages(this, revision, fragment, "body");
    return editState(
      await this.connection.request({
        operation: "pasteBodyFragment",
        revision,
        selection,
        fragment,
        profile,
      }),
    );
  }
  async selectedText(
    revision: number,
    selection: DocxSelection,
    cut = false,
  ): Promise<string> {
    const result = await this.connection.request({
      operation: "selectedText",
      revision,
      selection,
      cut,
    });
    if (typeof result !== "string")
      throw new Error("Invalid selection text returned by Wasm");
    return result;
  }
  async tableClipboard(
    revision: number,
    selection: DocxSelection,
    cut = false,
  ): Promise<DocxTableClipboard> {
    return docxTableClipboard(
      await this.connection.request({
        operation: "tableClipboard",
        revision,
        selection,
        cut,
      }),
    );
  }
  async tableFragmentImages(revision: number, fragment: string) {
    checkDocxTableEdit({ action: "pasteFragment", fragment });
    return docxFragmentImages(
      await this.connection.request({
        operation: "tableFragmentImages",
        revision,
        fragment,
      }),
      false,
    );
  }
}
