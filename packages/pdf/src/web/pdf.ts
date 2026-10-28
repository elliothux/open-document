import type { EngineHandle } from "@open-document/wasm";
import { engineModule } from "@open-document/wasm/loader";
import type { Operation } from "../worker/protocol.js";
import { Connection } from "@open-document/web-core/connection";
import {
  pdfResult,
  type PdfBudget,
  type PdfCommand,
  type PdfResult,
} from "../core/pdf.js";

/** One Worker owns the PDF source, page interpretation and editing history. */
export class PdfClient {
  private constructor(private readonly connection: Connection<Operation>) {}
  static async open(
    engine: EngineHandle,
    workerUrl: URL,
    signal?: AbortSignal,
  ): Promise<PdfClient> {
    const client = new PdfClient(
      new Connection<Operation>(new Worker(workerUrl, { type: "module" })),
    );
    try {
      await client.connection.initialize(
        { operation: "initialize", module: engineModule(engine) },
        signal,
      );
      return client;
    } catch (error) {
      client.dispose();
      throw error;
    }
  }
  async defaultBudget(): Promise<PdfBudget> {
    return this.execute({ operation: "defaultPdfBudget" });
  }
  async addFont(bytes: Uint8Array, identity: string): Promise<void> {
    await this.connection.request({ operation: "font", bytes, identity });
  }
  async execute<C extends PdfCommand>(command: C): Promise<PdfResult<C>> {
    return pdfResult(command, await this.connection.request(command));
  }
  dispose(): void {
    this.connection.dispose();
  }
}
