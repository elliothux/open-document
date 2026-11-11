import type { EngineHandle } from "@open-document/wasm";
import { engineModule } from "@open-document/wasm/loader";
import type { WorkerOperation } from "@open-document/web-core/protocol";
import type { Connection } from "@open-document/web-core/connection";
import { openWorkerConnection } from "@open-document/web-core/worker-connection";
import { decodeImage } from "@open-document/web-core/image";
import {
  checkPdfByteInput,
  type PdfInputLimits,
  type PdfBudget,
  type PdfCommand,
  type PdfRasterPixels,
  type PdfResult,
} from "../core/pdf.js";
export type { PdfInputLimits } from "../core/pdf.js";

type Operation = WorkerOperation<PdfCommand>;

/** One Worker owns the PDF source, page interpretation and editing history. */
export class PdfClient {
  private constructor(
    private readonly connection: Connection<Operation, PdfInputLimits>,
  ) {}
  static async open(
    engine: EngineHandle,
    workerUrl: URL,
    signal?: AbortSignal,
  ): Promise<PdfClient> {
    return new PdfClient(
      await openWorkerConnection<Operation, PdfInputLimits>(
        engineModule(engine),
        workerUrl,
        signal,
      ),
    );
  }
  async defaultBudget(): Promise<PdfBudget> {
    return this.execute({ operation: "defaultPdfBudget" });
  }
  async addFont(bytes: Uint8Array, identity: string): Promise<void> {
    await this.connection.request({ operation: "font", bytes, identity });
  }
  inputLimits(): PdfInputLimits {
    return this.connection.inputLimits();
  }
  async execute<C extends PdfCommand>(command: C): Promise<PdfResult<C>> {
    checkPdfByteInput(command, this.connection.inputLimits());
    return (await this.connection.request(command)) as PdfResult<C>;
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
  dispose(): void {
    this.connection.dispose();
  }
}
