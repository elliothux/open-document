import type { EngineHandle } from "@open-document/wasm";
import { engineModule } from "@open-document/wasm/loader";
import type { Connection } from "@open-document/web-core/connection";
import { openWorkerConnection } from "@open-document/web-core/worker-connection";
import type {
  OfficeCommand,
  WorkerOperation,
} from "@open-document/web-core/protocol";
import type { Budget } from "@open-document/wasm/abi/session";
import { type DocxCommand, type DocxResult } from "./core/docx-command.js";
import {
  checkDocxInput,
  checkDocxByteInput,
  type DocxInputLimits,
} from "./core/docx-input.js";
export type { DocxCommand, DocxResult } from "./core/docx-command.js";

type DocxOperation = WorkerOperation<OfficeCommand<DocxCommand>>;

/** An asynchronous Docx session. File I/O and platform resources belong to the caller. */
export class DocxWorkerSession {
  protected constructor(
    private readonly connection: Connection<DocxOperation, DocxInputLimits>,
  ) {}

  static async open(
    engine: EngineHandle,
    workerUrl: URL,
    signal?: AbortSignal,
  ): Promise<DocxWorkerSession> {
    return new DocxWorkerSession(await this.connect(engine, workerUrl, signal));
  }

  protected static connect(
    engine: EngineHandle,
    workerUrl: URL,
    signal?: AbortSignal,
  ) {
    return openWorkerConnection<DocxOperation, DocxInputLimits>(
      engineModule(engine),
      workerUrl,
      signal,
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

  protected checkCommand(command: DocxCommand): void {
    checkDocxInput(command, () => this.inputLimits());
    checkDocxByteInput(command, this.inputLimits());
  }

  async execute<C extends DocxCommand>(command: C): Promise<DocxResult<C>> {
    this.checkCommand(command);
    return (await this.connection.request(command)) as DocxResult<C>;
  }

  dispose(): void {
    this.connection.dispose();
  }
}
