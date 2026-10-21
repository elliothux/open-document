import { DocumentClipboard } from "./document-clipboard.js";
import type { DocxTableEdit } from "@open-document/wasm/foundation";

/** Table commands retain the editor's existing source transaction and queue. */
export abstract class DocumentTables extends DocumentClipboard {
  insertTable(rows: number, cols: number): Promise<void> {
    return this.review.edit(() =>
      this.review.client.insertTable(
        this.review.snapshot().revision,
        this.selection(),
        rows,
        cols,
        this.profile,
      ),
    );
  }
  editTable(change: DocxTableEdit): Promise<void> {
    return this.review.edit(() => {
      const args = [
        this.review.snapshot().revision,
        this.selection(),
        change,
      ] as const;
      return this.review.client.editTable(...args, this.profile);
    });
  }
}
