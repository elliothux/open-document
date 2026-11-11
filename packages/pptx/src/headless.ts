import type { EngineHandle } from "@open-document/wasm";
import { engineModule } from "@open-document/wasm/loader";
import type { Connection } from "@open-document/web-core/connection";
import { openWorkerConnection } from "@open-document/web-core/worker-connection";
import type {
  OfficeCommand,
  WorkerOperation,
} from "@open-document/web-core/protocol";
import type { Budget } from "@open-document/wasm/abi/session";
import { type PptxCommand, type PptxResult } from "./core/pptx.js";
import {
  checkPptxInput,
  preparePptxSearch,
  type PptxInputLimits,
} from "./core/pptx.js";
export type { PptxCommand, PptxResult } from "./core/pptx.js";

type Operation = WorkerOperation<OfficeCommand<PptxCommand>>;

/** An asynchronous Pptx session. File I/O and platform resources belong to the caller. */
export class PptxWorkerSession {
  protected constructor(
    private readonly connection: Connection<Operation, PptxInputLimits>,
  ) {}

  static async open(
    engine: EngineHandle,
    workerUrl: URL,
    signal?: AbortSignal,
  ): Promise<PptxWorkerSession> {
    return new PptxWorkerSession(await this.connect(engine, workerUrl, signal));
  }

  protected static connect(
    engine: EngineHandle,
    workerUrl: URL,
    signal?: AbortSignal,
  ) {
    return openWorkerConnection<Operation, PptxInputLimits>(
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

  inputLimits(): PptxInputLimits {
    return this.connection.inputLimits();
  }

  protected checkCommand(command: PptxCommand): void {
    checkPptxInput(command, this.inputLimits());
  }

  async execute<C extends PptxCommand>(command: C): Promise<PptxResult<C>> {
    this.checkCommand(command);
    const request =
      command.operation === "findPptx" ||
      command.operation === "replacePptxMatches"
        ? preparePptxSearch(command)
        : command;
    return (await this.connection.request(request)) as PptxResult<C>;
  }

  dispose(): void {
    this.connection.dispose();
  }
}
