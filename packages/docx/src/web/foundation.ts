export { pasteDocxCells, pasteDocxSelection } from "./clipboard-input.js";

export { checkDocxComment } from "../core/foundation.js";
export type * from "./foundation-types.js";
export {
  checkDocxHyperlink,
  checkDocxBookmark,
  highlightColors,
  DOCX_SOFT_BREAK,
  DOCX_PAGE_BREAK,
  DOCX_COLUMN_BREAK,
  listFormats,
  noteNumberFormats,
  sourceKinds,
} from "../core/foundation.js";

import type { EngineHandle } from "@open-document/wasm";
import { engineModule } from "@open-document/wasm/loader";
import type { Budget } from "@open-document/wasm/abi/session";
import type { Connection } from "@open-document/web-core/connection";
import type {
  OfficeCommand,
  WorkerOperation,
} from "@open-document/web-core/protocol";
import { openWorkerConnection } from "@open-document/web-core/worker-connection";
import type { DocxCommand, DocxResult } from "../core/docx-command.js";
export type { DocxCommand, DocxResult } from "../core/docx-command.js";
import {
  prepareDocxFragmentImages,
  prepareDocxImages,
} from "./document-fragment-images.js";
import {
  checkDocxInput,
  checkDocxByteInput,
  type DocxInputLimits,
} from "../core/docx-input.js";
export type { DocxInputLimits } from "../core/docx-input.js";

export type DocxOperation = WorkerOperation<OfficeCommand<DocxCommand>>;

/** One Worker owns the document; the client prepares platform images before pasting. */
export class FoundationClient {
  private constructor(
    private readonly connection: Connection<DocxOperation, DocxInputLimits>,
  ) {}
  static async open(
    engine: EngineHandle,
    workerUrl: URL,
    signal?: AbortSignal,
  ): Promise<FoundationClient> {
    return new FoundationClient(
      await openWorkerConnection<DocxOperation, DocxInputLimits>(
        engineModule(engine),
        workerUrl,
        signal,
      ),
    );
  }
  async defaultBudget(): Promise<Budget> {
    return (await this.connection.request({ operation: "budget" })) as Budget;
  }
  async addFont(bytes: Uint8Array, identity: string): Promise<void> {
    await this.connection.request({ operation: "font", bytes, identity });
  }
  inputLimits(): DocxInputLimits {
    return this.connection.inputLimits();
  }
  async execute<C extends DocxCommand>(command: C): Promise<DocxResult<C>> {
    checkDocxInput(command, () => this.inputLimits());
    checkDocxByteInput(command, this.inputLimits());
    if (
      command.operation === "pasteHtml" ||
      command.operation === "pasteMarkdown"
    ) {
      await prepareDocxImages(
        this,
        await this.execute({
          operation: "markupImages",
          revision: command.revision,
          kind: command.operation === "pasteHtml" ? "html" : "markdown",
          input:
            command.operation === "pasteHtml" ? command.html : command.markdown,
          mode: command.mode,
          preparePixels: true,
        }),
      );
    } else if (command.operation === "pasteBodyFragment") {
      await prepareDocxFragmentImages(
        this,
        command.revision,
        command.fragment,
        "body",
      );
    } else if (
      command.operation === "editTable" &&
      command.change.action === "pasteFragment"
    ) {
      await prepareDocxFragmentImages(
        this,
        command.revision,
        command.change.fragment,
      );
    }
    return (await this.connection.request(command)) as DocxResult<C>;
  }
  dispose(): void {
    this.connection.dispose();
  }
}
