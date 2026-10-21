import { DocumentReview } from "./document-review.js";
import type { DocxRuler, DocxRulerEdit } from "@open-document/wasm/foundation";
export type DocumentRuler = DocxRuler & { documentId: string };
import type { DocxPageSetup } from "@open-document/wasm/foundation";
import type { DocxPageBorders } from "@open-document/wasm/foundation";
import type { DocxPageNumbering } from "@open-document/wasm/foundation";
import type { DocxColumns } from "@open-document/wasm/foundation";
import type { EditorOutput } from "./editor-state.js";
import type {
  DocxRunningKind,
  DocxRunningVariant,
  DocxRunningContent,
  DocxBodyField,
  DocxBodyPageField,
  DocxSelection,
  DocxProtection,
  DocxShapeEdit,
} from "@open-document/wasm/foundation";
export type DocumentBodyPageField = DocxBodyPageField & { documentId: string };
export type DocumentProtection = DocxProtection & { documentId: string };

/** Document-wide page commands use the editor's existing read and edit queues. */
export abstract class DocumentPage extends DocumentReview {
  shapes() {
    return this.review.read(() =>
      this.review.client.shapes(this.review.snapshot().revision),
    );
  }
  editShape(revision: number, shape: DocxShapeEdit): Promise<void> {
    return this.review.edit(() =>
      this.review.client.editShape(revision, shape, this.profile),
    );
  }
  documentProtection(): Promise<DocumentProtection> {
    return this.review.read(async () => ({
      ...(await this.review.client.documentProtection(
        this.review.snapshot().revision,
      )),
      documentId: this.review.snapshot().documentId,
    }));
  }
  setDocumentProtection(
    source: DocumentProtection,
    enabled: boolean,
    password = "",
  ): Promise<void> {
    return this.review.edit(() => {
      const current = this.review.snapshot();
      if (
        source.documentId !== current.documentId ||
        source.revision !== current.revision
      )
        throw new Error("Document protection state is stale");
      return this.review.client.setDocumentProtection(
        source.revision,
        enabled,
        password,
      );
    });
  }
  protected abstract selection(): DocxSelection;
  bodyPageField(): Promise<DocumentBodyPageField> {
    return this.review.read(async () => {
      const state = this.review.snapshot();
      return {
        ...(await this.review.client.bodyPageField(
          state.revision,
          this.selection(),
        )),
        documentId: state.documentId,
      };
    });
  }
  editBodyPageField(
    source: DocumentBodyPageField,
    field: DocxBodyField,
  ): Promise<void> {
    return this.review.edit(() => {
      const current = this.review.snapshot();
      if (
        source.documentId !== current.documentId ||
        source.revision !== current.revision ||
        JSON.stringify(source.selection) !== JSON.stringify(this.selection())
      )
        throw new Error("Document or field selection changed");
      return this.review.client.editBodyPageField(
        source.revision,
        source.selection,
        field,
        this.profile,
      );
    });
  }
  insertBodyPageField(field: DocxBodyField): Promise<void> {
    return this.review.edit(() =>
      this.review.client.insertBodyPageField(
        this.review.snapshot().revision,
        field,
        this.profile,
      ),
    );
  }
  updateBodyPageFields(): Promise<void> {
    return this.review.edit(() =>
      this.review.client.updateBodyPageFields(
        this.review.snapshot().revision,
        this.profile,
      ),
    );
  }
  protected abstract downloadOutput(
    output: EditorOutput,
    filename: string,
  ): void;
  async downloadPdf(
    filename = "document.pdf",
    outputBytes = 67108864,
  ): Promise<void> {
    this.downloadOutput(await this.exportPdf(outputBytes), filename);
  }
  async downloadDocx(filename = "document.docx"): Promise<void> {
    this.downloadOutput(await this.saveDocx(), filename);
  }
  ruler(): Promise<DocumentRuler> {
    return this.review.read(async () => ({
      ...(await this.review.client.ruler(this.review.snapshot().revision)),
      documentId: this.review.snapshot().documentId,
    }));
  }
  editRuler(source: DocumentRuler, change: DocxRulerEdit): Promise<void> {
    return this.review.edit(() => {
      if (source.documentId !== this.review.snapshot().documentId)
        throw new Error("Ruler belongs to another document");
      return this.review.client.editRuler(source, change);
    });
  }
  setPageColumns(columns: DocxColumns | null): Promise<void> {
    return this.review.edit(() =>
      this.review.client.setPageColumns(
        this.review.snapshot().revision,
        columns,
        this.profile,
      ),
    );
  }
  setPageNumbering(numbering: DocxPageNumbering | null): Promise<void> {
    return this.review.edit(() =>
      this.review.client.setPageNumbering(
        this.review.snapshot().revision,
        numbering,
        this.profile,
      ),
    );
  }
  protected abstract readonly profile: Record<string, string>;
  unlinkRunningArea(
    kind: DocxRunningKind,
    variant: DocxRunningVariant,
  ): Promise<void> {
    return this.review.edit(() =>
      this.review.client.unlinkRunningArea(
        this.review.snapshot().revision,
        kind,
        variant,
        this.profile,
      ),
    );
  }
  runningArea(kind: DocxRunningKind, variant: DocxRunningVariant) {
    return this.review.read(() =>
      this.review.client.runningArea(
        this.review.snapshot().revision,
        kind,
        variant,
      ),
    );
  }
  setRunningArea(
    kind: DocxRunningKind,
    variant: DocxRunningVariant,
    content: DocxRunningContent[],
    distance: number,
  ): Promise<void> {
    return this.review.edit(() =>
      this.review.client.setRunningArea(
        this.review.snapshot().revision,
        kind,
        variant,
        content,
        distance,
        this.profile,
      ),
    );
  }
  protected abstract outputs(
    format: "docx" | "pdf" | "png" | "images" | "html" | "markdown",
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
  async exportHtml(outputBytes = 67108864): Promise<EditorOutput> {
    return (await this.outputs("html", outputBytes))[0]!;
  }
  async exportMarkdown(outputBytes = 67108864): Promise<EditorOutput> {
    return (await this.outputs("markdown", outputBytes))[0]!;
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
  setRunningOptions(first: boolean, even: boolean): Promise<void> {
    return this.review.edit(() =>
      this.review.client.setRunningOptions(
        this.review.snapshot().revision,
        first,
        even,
        this.profile,
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
