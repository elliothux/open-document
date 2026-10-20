import { FoundationPageClient } from "./foundation-page.js";
import {
  docxClipboard,
  docxTableClipboard,
  docxFragmentImages,
  checkDocxTableEdit,
  editState,
  type DocxTableClipboard,
  type DocxSelection,
} from "@open-document/wasm/foundation";
import { prepareDocxFragmentImages } from "./document-fragment-images.js";
export abstract class FoundationClipboardClient extends FoundationPageClient {
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
