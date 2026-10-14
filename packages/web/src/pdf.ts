import { Connection } from "./connection.js";
import {
  pdfResult,
  type PdfBudget,
  type PdfCommand,
  type PdfResult,
} from "@open-document/wasm/pdf";

/** One Worker owns the PDF source, page interpretation and editing history. */
export class PdfClient {
  private constructor(private readonly connection: Connection) {}
  static async open(wasm: ArrayBuffer, workerUrl: URL): Promise<PdfClient> {
    const client = new PdfClient(
      new Connection(new Worker(workerUrl, { type: "module" })),
    );
    try {
      await client.connection.request({ operation: "openPdfWorker", wasm });
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
