import { Connection } from "./connection.js";
import { decodeImage } from "./image.js";
import {
  pptxResult,
  checkPptxObjectEdit,
  checkPptxSlideEdit,
  preparePptxSearch,
  type PptxCommand,
  type PptxResult,
} from "@open-document/wasm/pptx";
import { resourceBudget, type Budget } from "@open-document/wasm/foundation";
export type {
  PptxObjectEdit,
  PptxDash,
  PptxCap,
  PptxJoin,
  PptxFindOptions,
  PptxSearchResult,
  PptxSlideEdit,
  PptxSection,
  PptxSections,
  PptxSlideLayouts,
  PptxTextFormat,
  PptxFormatting,
  PptxTextSpacing,
  PptxListFormat,
  PptxParagraphFormat,
  PptxParagraphFormatting,
} from "@open-document/wasm/pptx";

/** A Worker owns presentation state, layout, history and source bytes. */
export class PptxClient {
  private constructor(private readonly connection: Connection) {}
  static async open(
    wasm: ArrayBuffer,
    workerUrl: URL,
    signal?: AbortSignal,
  ): Promise<PptxClient> {
    const client = new PptxClient(
      new Connection(new Worker(workerUrl, { type: "module" })),
    );
    try {
      await client.connection.initialize(
        { operation: "openPresentation", wasm },
        signal,
      );
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
    if (command.operation === "editPptxObjects")
      checkPptxObjectEdit(command.change);
    if (
      command.operation === "editPptxObjects" &&
      (command.change.action === "insertImage" ||
        command.change.action === "replaceImage")
    ) {
      const { bitmap } = await decodeImage(command.change.bytes);
      bitmap.close();
    }
    if (command.operation === "editPptxSlides")
      checkPptxSlideEdit(command.change);
    const request =
      command.operation === "findPptx" ||
      command.operation === "replacePptxMatches"
        ? preparePptxSearch(command)
        : command;
    return pptxResult(command, await this.connection.request(request));
  }
  dispose(): void {
    this.connection.dispose();
  }
}
