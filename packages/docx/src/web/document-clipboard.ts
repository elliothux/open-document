import { DocumentPage } from "./document-page.js";
import { DOCX_SOFT_BREAK } from "../core/foundation.js";
import type { DocxPasteMode } from "../core/foundation.js";
/** Rich text uses the existing edit queue and core-owned resource transaction. */
export abstract class DocumentClipboard extends DocumentPage {
  /** Selects the body, or the text box containing the current caret. */
  selectAll(): Promise<void> {
    return this.review.edit(() =>
      this.review.client.selectAllDocx(this.review.snapshot().revision),
    );
  }
  abstract paste(text: string): Promise<void>;
  insertSoftBreak(): Promise<void> {
    return this.paste(DOCX_SOFT_BREAK);
  }
  pasteHtml(html: string, mode: DocxPasteMode = "source"): Promise<void> {
    return this.review.edit(() => {
      const state = this.review.snapshot();
      return this.review.client.pasteHtml(
        state.revision,
        this.selection(),
        html,
        this.profile,
        mode,
      );
    });
  }
  pasteMarkdown(
    markdown: string,
    mode: DocxPasteMode = "source",
  ): Promise<void> {
    return this.review.edit(() => {
      const state = this.review.snapshot();
      return this.review.client.pasteMarkdown(
        state.revision,
        this.selection(),
        markdown,
        this.profile,
        mode,
      );
    });
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
