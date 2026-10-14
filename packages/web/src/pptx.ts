import { Connection } from "./connection.js";
import {
  pptxResult,
  type PptxCommand,
  type PptxResult,
} from "@open-document/wasm/pptx";
import { resourceBudget, type Budget } from "@open-document/wasm/foundation";

/** A Worker owns presentation state, layout, history and source bytes. */
export class PptxClient {
  private constructor(private readonly connection: Connection) {}
  static async open(wasm: ArrayBuffer, workerUrl: URL): Promise<PptxClient> {
    const client = new PptxClient(
      new Connection(new Worker(workerUrl, { type: "module" })),
    );
    try {
      await client.connection.request({ operation: "openPresentation", wasm });
      return client;
    } catch (error) {
      client.dispose();
      throw error;
    }
  }
  async defaultBudget(): Promise<Budget> {
    return resourceBudget(
      await this.connection.request({ operation: "budget" }),
    );
  }
  async addFont(bytes: Uint8Array, identity: string): Promise<void> {
    await this.connection.request({ operation: "font", bytes, identity });
  }
  async execute<C extends PptxCommand>(command: C): Promise<PptxResult<C>> {
    return pptxResult(command, await this.connection.request(command));
  }
  dispose(): void {
    this.connection.dispose();
  }
}
