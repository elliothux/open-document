import type {
  PdfQuery,
  PdfFieldDesign,
  PdfPlacement,
  PdfOfficeBudget,
  PdfOfficeConversion,
  PdfRedactionRegion,
  PdfRedactionPreview,
  PdfAnnotationStyle,
} from "../core/pdf.js";
import type { EditorOutput } from "@open-document/web-core/editor-state";
import type { EditCommand } from "./pdf-draft.js";
import { PdfViewer } from "./pdf-viewer.js";
import { pdfPageImages } from "./pdf-output.js";
import { preparePdfOutputImages } from "./pdf-output-images.js";
import { drawRedactionPreview } from "./pdf-redaction.js";
import { decodeImage } from "@open-document/web-core/image";

/** SDK operations share the editor's transaction and draft barriers. */
export abstract class PdfOperations extends PdfViewer {
  clearRedactionPreview(): void {
    if (!this.closed && !this.closing) this.surface.clearOverlay(this.scale);
  }
  insertStamp(
    bytes: Uint8Array,
    signature = false,
    style?: PdfAnnotationStyle,
  ): Promise<PdfQuery> {
    this.checkDraft();
    this.cancelSearch();
    return this.commit(async (revision) => {
      const image = await decodeImage(bytes);
      try {
        const page = this.state.pages.find(
          (page) => page.id === this.state.page,
        )!;
        const x = Math.min(20, page.width / 10),
          y = Math.min(20, page.height / 10);
        const width = Math.min(
          200,
          page.width - x * 2,
          ((page.height - y * 2) * image.bitmap.width) / image.bitmap.height,
        );
        const placement = {
          x,
          y,
          width,
          height: (width * image.bitmap.height) / image.bitmap.width,
          rotation: 0,
        };
        return {
          operation: "addPdfStampAnnotation",
          revision,
          page: page.id,
          style: style ?? {
            placement,
            color: "000000",
            opacity: 1,
            border: 0,
            author: "",
            text: "",
          },
          signature,
          pixelWidth: image.bitmap.width,
          pixelHeight: image.bitmap.height,
          bytes: image.rgba,
        };
      } finally {
        image.bitmap.close();
      }
    });
  }
  async convertOffice(
    format: "docx" | "xlsx" | "pptx",
    acceptLoss = false,
    pages = this.state.pages.map((page) => page.id),
    budget?: PdfOfficeBudget,
  ): Promise<PdfOfficeConversion & { output: EditorOutput | null }> {
    this.checkDraft();
    return this.enqueue(async () => {
      const revision = this.state.revision;
      await preparePdfOutputImages(this.client, revision, pages, this.profile);
      const limits =
        budget ??
        (await this.client.execute({ operation: "defaultPdfOfficeBudget" }));
      const result = await this.client.execute({
        operation: "convertPdfOffice",
        revision,
        format,
        pages,
        acceptLoss,
        budget: limits,
        profile: this.profile,
      });
      return {
        ...result,
        output: result.bytes
          ? this.observable.output(result.revision, format, result.bytes)
          : null,
      };
    }, true);
  }
  async previewRedaction(
    regions: PdfRedactionRegion[],
  ): Promise<PdfRedactionPreview> {
    this.checkDraft();
    return this.enqueue(async () => {
      const revision = this.state.revision;
      await preparePdfOutputImages(
        this.client,
        revision,
        this.state.pages.map((page) => page.id),
        this.profile,
      );
      const preview = await this.client.execute({
        operation: "previewPdfRedaction",
        revision,
        regions,
        profile: this.profile,
      });
      if (this.layout)
        drawRedactionPreview(
          this.surface,
          preview,
          this.state.page,
          this.scale,
        );
      return preview;
    }, true);
  }
  async exportRedaction(
    regions: PdfRedactionRegion[],
  ): Promise<{ output: EditorOutput; warnings: readonly string[] }> {
    this.checkDraft();
    return this.enqueue(async () => {
      const revision = this.state.revision;
      await preparePdfOutputImages(
        this.client,
        revision,
        this.state.pages.map((page) => page.id),
        this.profile,
      );
      const result = await this.client.execute({
        operation: "exportPdfRedaction",
        revision,
        regions,
        profile: this.profile,
      });
      return {
        output: this.observable.output(
          result.revision,
          "pdf",
          result.bytes,
          false,
        ),
        warnings: result.warnings,
      };
    }, true);
  }
  splitPage(regions: PdfPlacement[]): Promise<PdfQuery> {
    this.checkDraft();
    this.cancelSearch();
    return this.commit((revision) => ({
      operation: "splitPdfPage",
      revision,
      page: this.state.page,
      regions,
    }));
  }
  splitPageGrid(columns: number, rows: number): Promise<PdfQuery> {
    this.checkDraft();
    this.cancelSearch();
    return this.commit((revision) => ({
      operation: "splitPdfPageGrid",
      revision,
      page: this.state.page,
      columns,
      rows,
    }));
  }
  nupPages(
    pages: string[],
    columns: number,
    rows: number,
    width: number,
    height: number,
  ): Promise<PdfQuery> {
    this.checkDraft();
    this.cancelSearch();
    return this.commit((revision) => ({
      operation: "nupPdfPages",
      revision,
      pages,
      columns,
      rows,
      width,
      height,
    }));
  }
  copyField(field: string, name: string, dx = 20, dy = 20): Promise<PdfQuery> {
    this.checkDraft();
    this.cancelSearch();
    return this.commit((revision) => ({
      operation: "duplicatePdfField",
      revision,
      field,
      name,
      dx,
      dy,
    }));
  }
  renameField(field: string, name: string): Promise<PdfQuery> {
    this.checkDraft();
    this.cancelSearch();
    return this.commit((revision) => ({
      operation: "renamePdfField",
      revision,
      field,
      name,
    }));
  }
  removeField(field: string): Promise<PdfQuery> {
    this.checkDraft();
    this.cancelSearch();
    return this.commit((revision) => ({
      operation: "deletePdfField",
      revision,
      field,
    }));
  }
  async splitFiles(
    groups = this.state.pages.map((page) => [page.id]),
  ): Promise<readonly { name: string; output: EditorOutput }[]> {
    this.checkDraft();
    return this.enqueue(async () => {
      const result = await this.client.execute({
        operation: "splitPdfFiles",
        revision: this.state.revision,
        groups,
      });
      return result.files.map((file) => ({
        name: file.name,
        output: this.observable.output(
          result.revision,
          "pdf",
          file.bytes,
          false,
        ),
      }));
    }, true);
  }
  async exportPageImages(
    format: "png" | "jpeg" = "png",
    pages = this.state.pages.map((page) => page.id),
    scale = 1,
    outputBytes = 67108864,
  ): Promise<readonly EditorOutput[]> {
    this.checkDraft();
    return this.enqueue(async () => {
      const revision = this.state.revision;
      const buffers = await pdfPageImages(
        this.client,
        revision,
        pages,
        this.profile,
        format,
        scale,
        outputBytes,
        () => {
          if (this.closed) throw new Error("Editor is disposed");
        },
      );
      return buffers.map((bytes) =>
        this.observable.output(revision, format, bytes),
      );
    }, true);
  }
  async exportText(
    format: "html" | "markdown",
    pages = this.state.pages.map((page) => page.id),
  ): Promise<{ output: EditorOutput; warnings: readonly string[] }> {
    this.checkDraft();
    return this.enqueue(async () => {
      await preparePdfOutputImages(
        this.client,
        this.state.revision,
        pages,
        this.profile,
        false,
      );
      const result = await this.client.execute({
        operation: "exportPdfText",
        revision: this.state.revision,
        pages,
        format,
        profile: this.profile,
      });
      this.pageDiagnostics = [
        ...new Set([...this.pageDiagnostics, ...result.warnings]),
      ];
      this.publish();
      return {
        output: this.observable.output(result.revision, format, result.bytes),
        warnings: result.warnings,
      };
    }, true);
  }
  protected abstract commit(
    command: (revision: number) => EditCommand | Promise<EditCommand>,
  ): Promise<PdfQuery>;
  async movePage(delta: number): Promise<PdfQuery> {
    this.checkDraft();
    this.cancelSearch();
    return this.commit((revision) => {
      const pages = this.state.pages.map((page) => page.id),
        index = pages.indexOf(this.state.page),
        next = index + delta;
      if (!Number.isInteger(delta) || next < 0 || next >= pages.length)
        throw new Error("PDF page cannot move further");
      [pages[index], pages[next]] = [pages[next]!, pages[index]!];
      return { operation: "reorderPdfPages", revision, pages };
    });
  }
  async rotate(degrees: number): Promise<PdfQuery> {
    this.checkDraft();
    this.cancelSearch();
    return this.commit((revision) => ({
      operation: "rotatePdfPages",
      revision,
      pages: [this.state.page],
      degrees,
    }));
  }
  async insertPages(
    bytes: Uint8Array,
    index = this.state.pages.length,
    pages: string[] = [],
  ): Promise<PdfQuery> {
    this.checkDraft();
    this.cancelSearch();
    return this.commit((revision) => ({
      operation: "insertPdfPages",
      revision,
      bytes,
      index,
      pages,
    }));
  }
  async insertBlankPage(width = 595, height = 842): Promise<PdfQuery> {
    this.checkDraft();
    this.cancelSearch();
    const index =
      this.state.pages.findIndex((page) => page.id === this.state.page) + 1;
    return this.commit((revision) => ({
      operation: "insertBlankPdfPage",
      revision,
      index,
      width,
      height,
    }));
  }
  async cropPage(
    x: number,
    y: number,
    width: number,
    height: number,
  ): Promise<PdfQuery> {
    this.checkDraft();
    this.cancelSearch();
    return this.commit((revision) => ({
      operation: "cropPdfPage",
      revision,
      page: this.state.page,
      x,
      y,
      width,
      height,
    }));
  }
  async resizePage(
    width: number,
    height: number,
    scaleContent: boolean,
    anchor: "top-left" | "center" = "top-left",
  ): Promise<PdfQuery> {
    this.checkDraft();
    this.cancelSearch();
    return this.commit((revision) => ({
      operation: "resizePdfPage",
      revision,
      page: this.state.page,
      width,
      height,
      scaleContent,
      anchor,
    }));
  }
  async replacePage(bytes: Uint8Array): Promise<PdfQuery> {
    this.checkDraft();
    this.cancelSearch();
    return this.commit((revision) => ({
      operation: "replacePdfPages",
      revision,
      bytes,
      pages: [],
      index: this.state.pages.findIndex((page) => page.id === this.state.page),
      replace: [this.state.page],
    }));
  }
  async extractPages(pages = [this.state.page]): Promise<EditorOutput> {
    this.checkDraft();
    return this.enqueue(async () => {
      const output = await this.client.execute({
        operation: "extractPdfPages",
        revision: this.state.revision,
        pages,
      });
      return this.observable.output(
        output.revision,
        "pdf",
        output.bytes,
        false,
      );
    }, true);
  }
  async deletePage(): Promise<PdfQuery> {
    this.checkDraft();
    this.cancelSearch();
    return this.commit((revision) => ({
      operation: "deletePdfPages",
      revision,
      pages: [this.state.page],
    }));
  }
  addNote(page: string, x: number, y: number, text: string): Promise<PdfQuery> {
    this.checkDraft();
    return this.commit((revision) => ({
      operation: "addPdfNote",
      revision,
      page,
      x,
      y,
      text,
    }));
  }
  createField(spec: PdfFieldDesign): Promise<PdfQuery> {
    this.checkDraft();
    return this.commit((revision) => ({
      operation: "createPdfField",
      revision,
      page: this.state.page,
      spec,
      profile: this.profile,
    }));
  }
  setFieldValue(
    field: string,
    value: string | boolean | string[],
  ): Promise<PdfQuery> {
    this.checkDraft();
    return this.commit((revision) => ({
      operation: "setPdfFieldValue",
      revision,
      field,
      value,
      profile: this.profile,
    }));
  }
  updateAnnotation(
    page: string,
    annotation: string,
    text: string,
  ): Promise<PdfQuery> {
    this.checkDraft();
    return this.commit((revision) => ({
      operation: "updatePdfAnnotation",
      revision,
      page,
      annotation,
      text,
    }));
  }

  async highlight(
    kind: "Highlight" | "Underline" | "StrikeOut" = "Highlight",
  ): Promise<PdfQuery> {
    this.checkDraft();
    this.cancelSearch();
    return this.commit((revision) => {
      if (!this.layout) throw new Error("PDF page is not displayed");
      return {
        operation: "markPdfText",
        kind,
        revision,
        layoutId: this.layout.id,
      };
    });
  }
  async undo(): Promise<PdfQuery> {
    this.checkDraft();
    this.cancelSearch();
    return this.commit((revision) => ({ operation: "undoPdf", revision }));
  }
  async redo(): Promise<PdfQuery> {
    this.checkDraft();
    this.cancelSearch();
    return this.commit((revision) => ({ operation: "redoPdf", revision }));
  }
}
