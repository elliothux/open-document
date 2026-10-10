import { Connection } from "./connection";
import type { Operation } from "./protocol";

/** Plain-text POC host. This is not a DOCX/XLSX/PPTX editor. */
export class TextClient {
  private constructor(private readonly connection: Connection) {}
  static async open(
    text: string,
    wasm: ArrayBuffer,
    workerUrl: URL,
  ): Promise<TextClient> {
    const client = new TextClient(
      new Connection(new Worker(workerUrl, { type: "module" })),
    );
    try {
      await client.request({ operation: "open", text, wasm });
      return client;
    } catch (error) {
      client.dispose();
      throw error;
    }
  }
  private async request(operation: Operation): Promise<string> {
    const result = await this.connection.request(operation);
    if (typeof result !== "string") throw new Error("Invalid text response");
    return result;
  }
  read(): Promise<string> {
    return this.request({ operation: "read" });
  }
  replace(start: number, end: number, text: string): Promise<string> {
    return this.request({ operation: "replace", start, end, text });
  }
  undo(): Promise<string> {
    return this.request({ operation: "undo" });
  }
  dispose(): void {
    this.connection.dispose();
  }
}
