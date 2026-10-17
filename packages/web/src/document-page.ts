import { DocumentReview } from "./document-review.js";
import type { DocxPageSetup } from "@open-document/wasm/foundation";
import type { DocxPageBorders } from "@open-document/wasm/foundation";
import type { EditorOutput } from "./editor-state.js";

/** Document-wide page commands use the editor's existing read and edit queues. */
export abstract class DocumentPage extends DocumentReview {
  protected abstract outputs(
    format: "docx" | "pdf" | "png" | "images",
    outputBytes?: number,
    scale?: number,
  ): Promise<readonly EditorOutput[]>;
  /** A barrier: later input cannot change the returned revision or bytes. */
  async saveDocx(): Promise<EditorOutput> {
    return (await this.outputs("docx"))[0]!;
  }
  async exportPdf(outputBytes = 67108864): Promise<EditorOutput> {
    return (await this.outputs("pdf", outputBytes))[0]!;
  }
  /** Exports the current page at pixels per point, independent of preview zoom and DPR. */
  async exportPng(scale = 1, outputBytes = 67108864): Promise<EditorOutput> {
    return (await this.outputs("png", outputBytes, scale))[0]!;
  }
  /** Exports all pages in order at one revision, with a shared byte budget. */
  exportPageImages(
    scale = 1,
    outputBytes = 67108864,
  ): Promise<readonly EditorOutput[]> {
    return this.outputs("images", outputBytes, scale);
  }
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
