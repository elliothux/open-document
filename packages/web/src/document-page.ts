import { DocumentReview } from "./document-review.js";
import type { DocxPageSetup } from "@open-document/wasm/foundation";
import type { DocxPageBorders } from "@open-document/wasm/foundation";

/** Document-wide page commands use the editor's existing read and edit queues. */
export class DocumentPage extends DocumentReview {
  setPageBorders(borders: DocxPageBorders | null): Promise<void> {
    return this.review.edit(() =>
      this.review.client.setPageBorders(
        this.review.snapshot().revision,
        borders,
      ),
    );
  }
  pageSetup() {
    return this.review.read(() =>
      this.review.client.pageSetup(this.review.snapshot().revision),
    );
  }
  setPageSetup(page: DocxPageSetup): Promise<void> {
    return this.review.edit(() =>
      this.review.client.setPageSetup(this.review.snapshot().revision, page),
    );
  }
  setPageBackground(color: string | null): Promise<void> {
    return this.review.edit(() =>
      this.review.client.setPageBackground(
        this.review.snapshot().revision,
        color,
      ),
    );
  }
}
