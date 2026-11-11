import type { EngineHandle } from "@open-document/wasm";
import { decodeImage } from "@open-document/web-core/image";
import type { PdfCommand, PdfRasterPixels } from "../core/pdf.js";
export type { PdfInputLimits } from "../core/pdf.js";
import { PdfWorkerSession } from "../headless.js";

import { checkViewCommand } from "@open-document/web-core/view-mode";

const viewCommands = new Set<PdfCommand["operation"]>([
  "queryPdf",
  "renderPdfPage",
  "releasePdfView",
  "hitTestPdf",
  "selectPdf",
  "selectPdfRange",
  "selectedPdfRange",
  "selectedPdfText",
  "searchPdfPage",
  "extractPdfText",
  "imagePdf",
  "decodedImagePdf",
  "pdfNavigation",
  "pdfMetadata",
  "pdfObjects",
  "pdfAnnotation",
  "pdfFieldDesign",
  "savePdf",
  "extractPdfPages",
  "exportPdfText",
  "defaultPdfOfficeBudget",
  "convertPdfOffice",
  "rasterHeaderPdf",
]);

export class PdfClient extends PdfWorkerSession {
  readOnly = false;

  protected override checkCommand(command: PdfCommand): void {
    checkViewCommand(this.readOnly, viewCommands, command.operation);
    super.checkCommand(command);
  }

  static override async open(
    engine: EngineHandle,
    workerUrl: URL,
    signal?: AbortSignal,
  ): Promise<PdfClient> {
    return new PdfClient(await this.connect(engine, workerUrl, signal));
  }
  async decodeRaster(bytes: Uint8Array): Promise<PdfRasterPixels> {
    const source = new Blob([new Uint8Array(bytes).buffer]);
    const windowBytes =
      source.size <= this.inputLimits().rgbaBytes ? source.size : 65536;
    let offset = 0;
    while (true) {
      const result = await this.execute({
        operation: "rasterHeaderPdf",
        bytes: new Uint8Array(
          await source.slice(offset, offset + windowBytes).arrayBuffer(),
        ),
        offset,
        total: source.size,
        decode: true,
      });
      if ("bytes" in result) return result;
      if (!("nextOffset" in result)) {
        const { bitmap, rgba } = await decodeImage(source, result);
        const { width, height } = bitmap;
        bitmap.close();
        return { width, height, bytes: rgba };
      }
      offset = result.nextOffset;
    }
  }
}
