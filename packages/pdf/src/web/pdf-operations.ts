import type { PdfClient } from "./pdf.js";
import type { PdfCanvas } from "./pdf-canvas.js";
import type {
  PdfQuery,
  PdfLayout,
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
import { pdfPageImages } from "./pdf-output.js";
import { preparePdfOutputImages } from "./pdf-output-images.js";
import { drawRedactionPreview } from "./pdf-redaction.js";

/** SDK operations share the editor's transaction and draft barriers. */
interface PdfOperationHost {
  state(): PdfQuery;
  view(): {
    layout: PdfLayout | undefined;
    surface: PdfCanvas;
    scale: number;
    closed: boolean;
    closing: boolean;
  };
  checkDraft(): void;
  cancelSearch(): void;
  commit(
    command: (revision: number) => EditCommand | Promise<EditCommand>,
  ): Promise<PdfQuery>;
  enqueue<T>(action: () => Promise<T>, output?: boolean): Promise<T>;
  output(
    revision: number,
    format: EditorOutput["format"],
    bytes: Uint8Array,
    canConfirmSave?: boolean,
  ): EditorOutput;
  warnings(warnings: readonly string[]): void;
}

export function createPdfOperations(
  client: PdfClient,
  profile: Record<string, string>,
  host: PdfOperationHost,
) {
  return {
    clearRedactionPreview(): void {
      const view = host.view();
      if (!view.closed && !view.closing) view.surface.clearOverlay(view.scale);
    },
    insertStamp(
      bytes: Uint8Array,
      signature = false,
      style?: PdfAnnotationStyle,
    ): Promise<PdfQuery> {
      host.checkDraft();
      host.cancelSearch();
      return host.commit(async (revision) => {
        const image = await client.decodeRaster(bytes);
        const page = host
          .state()
          .pages.find((page) => page.id === host.state().page)!;
        const x = Math.min(20, page.width / 10),
          y = Math.min(20, page.height / 10);
        const width = Math.min(
          200,
          page.width - x * 2,
          ((page.height - y * 2) * image.width) / image.height,
        );
        const placement = {
          x,
          y,
          width,
          height: (width * image.height) / image.width,
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
          pixelWidth: image.width,
          pixelHeight: image.height,
          bytes: image.bytes,
        };
      });
    },

    async convertOffice(
      format: "docx" | "xlsx" | "pptx",
      acceptLoss = false,
      pages = host.state().pages.map((page) => page.id),
      budget?: PdfOfficeBudget,
    ): Promise<PdfOfficeConversion & { output: EditorOutput | null }> {
      host.checkDraft();
      return host.enqueue(async () => {
        const revision = host.state().revision;
        await preparePdfOutputImages(client, revision, pages, profile);
        const limits =
          budget ??
          (await client.execute({ operation: "defaultPdfOfficeBudget" }));
        const result = await client.execute({
          operation: "convertPdfOffice",
          revision,
          format,
          pages,
          acceptLoss,
          budget: limits,
          profile: profile,
        });
        return {
          ...result,
          output: result.bytes
            ? host.output(result.revision, format, result.bytes)
            : null,
        };
      }, true);
    },

    async previewRedaction(
      regions: PdfRedactionRegion[],
    ): Promise<PdfRedactionPreview> {
      host.checkDraft();
      return host.enqueue(async () => {
        const revision = host.state().revision;
        await preparePdfOutputImages(
          client,
          revision,
          host.state().pages.map((page) => page.id),
          profile,
        );
        const preview = await client.execute({
          operation: "previewPdfRedaction",
          revision,
          regions,
          profile: profile,
        });
        const view = host.view();
        if (view.layout)
          drawRedactionPreview(
            view.surface,
            preview,
            host.state().page,
            view.scale,
          );
        return preview;
      }, true);
    },

    async exportRedaction(
      regions: PdfRedactionRegion[],
    ): Promise<{ output: EditorOutput; warnings: readonly string[] }> {
      host.checkDraft();
      return host.enqueue(async () => {
        const revision = host.state().revision;
        await preparePdfOutputImages(
          client,
          revision,
          host.state().pages.map((page) => page.id),
          profile,
        );
        const result = await client.execute({
          operation: "exportPdfRedaction",
          revision,
          regions,
          profile: profile,
        });
        return {
          output: host.output(result.revision, "pdf", result.bytes, false),
          warnings: result.warnings,
        };
      }, true);
    },

    splitPage(regions: PdfPlacement[]): Promise<PdfQuery> {
      host.checkDraft();
      host.cancelSearch();
      return host.commit((revision) => ({
        operation: "splitPdfPage",
        revision,
        page: host.state().page,
        regions,
      }));
    },

    splitPageGrid(columns: number, rows: number): Promise<PdfQuery> {
      host.checkDraft();
      host.cancelSearch();
      return host.commit((revision) => ({
        operation: "splitPdfPageGrid",
        revision,
        page: host.state().page,
        columns,
        rows,
      }));
    },

    nupPages(
      pages: string[],
      columns: number,
      rows: number,
      width: number,
      height: number,
    ): Promise<PdfQuery> {
      host.checkDraft();
      host.cancelSearch();
      return host.commit((revision) => ({
        operation: "nupPdfPages",
        revision,
        pages,
        columns,
        rows,
        width,
        height,
      }));
    },

    copyField(
      field: string,
      name: string,
      dx = 20,
      dy = 20,
    ): Promise<PdfQuery> {
      host.checkDraft();
      host.cancelSearch();
      return host.commit((revision) => ({
        operation: "duplicatePdfField",
        revision,
        field,
        name,
        dx,
        dy,
      }));
    },

    renameField(field: string, name: string): Promise<PdfQuery> {
      host.checkDraft();
      host.cancelSearch();
      return host.commit((revision) => ({
        operation: "renamePdfField",
        revision,
        field,
        name,
      }));
    },

    removeField(field: string): Promise<PdfQuery> {
      host.checkDraft();
      host.cancelSearch();
      return host.commit((revision) => ({
        operation: "deletePdfField",
        revision,
        field,
      }));
    },

    async splitFiles(
      groups = host.state().pages.map((page) => [page.id]),
    ): Promise<readonly { name: string; output: EditorOutput }[]> {
      host.checkDraft();
      return host.enqueue(async () => {
        const result = await client.execute({
          operation: "splitPdfFiles",
          revision: host.state().revision,
          groups,
        });
        return result.files.map((file) => ({
          name: file.name,
          output: host.output(result.revision, "pdf", file.bytes, false),
        }));
      }, true);
    },

    async exportPageImages(
      format: "png" | "jpeg" = "png",
      pages = host.state().pages.map((page) => page.id),
      scale = 1,
      outputBytes = client.inputLimits().exportBytes,
    ): Promise<readonly EditorOutput[]> {
      host.checkDraft();
      return host.enqueue(async () => {
        const revision = host.state().revision;
        const buffers = await pdfPageImages(
          client,
          revision,
          pages,
          profile,
          format,
          scale,
          outputBytes,
          () => {
            if (host.view().closed) throw new Error("Editor is disposed");
          },
        );
        return buffers.map((bytes) => host.output(revision, format, bytes));
      }, true);
    },

    async exportText(
      format: "html" | "markdown",
      pages = host.state().pages.map((page) => page.id),
    ): Promise<{ output: EditorOutput; warnings: readonly string[] }> {
      host.checkDraft();
      return host.enqueue(async () => {
        await preparePdfOutputImages(
          client,
          host.state().revision,
          pages,
          profile,
          false,
        );
        const result = await client.execute({
          operation: "exportPdfText",
          revision: host.state().revision,
          pages,
          format,
          profile: profile,
        });
        host.warnings(result.warnings);
        return {
          output: host.output(result.revision, format, result.bytes),
          warnings: result.warnings,
        };
      }, true);
    },

    async movePage(delta: number): Promise<PdfQuery> {
      host.checkDraft();
      host.cancelSearch();
      return host.commit((revision) => {
        const pages = host.state().pages.map((page) => page.id),
          index = pages.indexOf(host.state().page),
          next = index + delta;
        if (!Number.isInteger(delta) || next < 0 || next >= pages.length)
          throw new Error("PDF page cannot move further");
        [pages[index], pages[next]] = [pages[next]!, pages[index]!];
        return { operation: "reorderPdfPages", revision, pages };
      });
    },

    async rotate(degrees: number): Promise<PdfQuery> {
      host.checkDraft();
      host.cancelSearch();
      return host.commit((revision) => ({
        operation: "rotatePdfPages",
        revision,
        pages: [host.state().page],
        degrees,
      }));
    },

    async insertPages(
      bytes: Uint8Array,
      index = host.state().pages.length,
      pages: string[] = [],
    ): Promise<PdfQuery> {
      host.checkDraft();
      host.cancelSearch();
      return host.commit((revision) => ({
        operation: "insertPdfPages",
        revision,
        bytes,
        index,
        pages,
      }));
    },

    async insertBlankPage(width = 595, height = 842): Promise<PdfQuery> {
      host.checkDraft();
      host.cancelSearch();
      const index =
        host.state().pages.findIndex((page) => page.id === host.state().page) +
        1;
      return host.commit((revision) => ({
        operation: "insertBlankPdfPage",
        revision,
        index,
        width,
        height,
      }));
    },

    async cropPage(
      x: number,
      y: number,
      width: number,
      height: number,
    ): Promise<PdfQuery> {
      host.checkDraft();
      host.cancelSearch();
      return host.commit((revision) => ({
        operation: "cropPdfPage",
        revision,
        page: host.state().page,
        x,
        y,
        width,
        height,
      }));
    },

    async resizePage(
      width: number,
      height: number,
      scaleContent: boolean,
      anchor: "top-left" | "center" = "top-left",
    ): Promise<PdfQuery> {
      host.checkDraft();
      host.cancelSearch();
      return host.commit((revision) => ({
        operation: "resizePdfPage",
        revision,
        page: host.state().page,
        width,
        height,
        scaleContent,
        anchor,
      }));
    },

    async replacePage(bytes: Uint8Array): Promise<PdfQuery> {
      host.checkDraft();
      host.cancelSearch();
      return host.commit((revision) => ({
        operation: "replacePdfPages",
        revision,
        bytes,
        pages: [],
        index: host
          .state()
          .pages.findIndex((page) => page.id === host.state().page),
        replace: [host.state().page],
      }));
    },

    async extractPages(pages = [host.state().page]): Promise<EditorOutput> {
      host.checkDraft();
      return host.enqueue(async () => {
        const output = await client.execute({
          operation: "extractPdfPages",
          revision: host.state().revision,
          pages,
        });
        return host.output(output.revision, "pdf", output.bytes, false);
      }, true);
    },

    async deletePage(): Promise<PdfQuery> {
      host.checkDraft();
      host.cancelSearch();
      return host.commit((revision) => ({
        operation: "deletePdfPages",
        revision,
        pages: [host.state().page],
      }));
    },

    addNote(
      page: string,
      x: number,
      y: number,
      text: string,
    ): Promise<PdfQuery> {
      host.checkDraft();
      return host.commit((revision) => ({
        operation: "addPdfNote",
        revision,
        page,
        x,
        y,
        text,
      }));
    },

    createField(spec: PdfFieldDesign): Promise<PdfQuery> {
      host.checkDraft();
      return host.commit((revision) => ({
        operation: "createPdfField",
        revision,
        page: host.state().page,
        spec,
        profile: profile,
      }));
    },

    setFieldValue(
      field: string,
      value: string | boolean | string[],
    ): Promise<PdfQuery> {
      host.checkDraft();
      return host.commit((revision) => ({
        operation: "setPdfFieldValue",
        revision,
        field,
        value,
        profile: profile,
      }));
    },

    updateAnnotation(
      page: string,
      annotation: string,
      text: string,
    ): Promise<PdfQuery> {
      host.checkDraft();
      return host.commit((revision) => ({
        operation: "updatePdfAnnotation",
        revision,
        page,
        annotation,
        text,
      }));
    },

    async highlight(
      kind: "Highlight" | "Underline" | "StrikeOut" = "Highlight",
    ): Promise<PdfQuery> {
      host.checkDraft();
      host.cancelSearch();
      return host.commit((revision) => {
        const layout = host.view().layout;
        if (!layout) throw new Error("PDF page is not displayed");
        return {
          operation: "markPdfText",
          kind,
          revision,
          layoutId: layout.id,
        };
      });
    },
  };
}
