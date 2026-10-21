import { DocumentPage } from "./document-page.js";
import { DOCX_SOFT_BREAK } from "@open-document/wasm/foundation";
/** Rich text uses the existing edit queue and core-owned resource transaction. */
export abstract class DocumentClipboard extends DocumentPage {
  abstract paste(text: string): Promise<void>;
  insertSoftBreak(): Promise<void> {
    return this.paste(DOCX_SOFT_BREAK);
  }
  pasteFragment(fragment: string): Promise<void> {
    return this.review.edit(() => {
      const state = this.review.snapshot();
      return this.review.client.pasteBodyFragment(
        state.revision,
        this.selection(),
        fragment,
        this.profile,
      );
    });
  }
}
