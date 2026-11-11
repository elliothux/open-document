import type { EngineHandle } from "@open-document/wasm";
import { engineModule } from "@open-document/wasm/loader";
import type { Connection } from "@open-document/web-core/connection";
import { openWorkerConnection } from "@open-document/web-core/worker-connection";
import type {
  OfficeCommand,
  WorkerOperation,
} from "@open-document/web-core/protocol";
import type { Budget } from "@open-document/wasm/abi/session";
import {
  decodeXlsxResult,
  type XlsxCommand,
  type XlsxResult,
} from "./core/xlsx-command.js";
import { checkXlsxByteInput, type XlsxInputLimits } from "./core/xlsx.js";
import { spreadsheetDate } from "./core/xlsx-filter.js";
export type { XlsxCommand, XlsxResult } from "./core/xlsx-command.js";

type XlsxOperation = WorkerOperation<OfficeCommand<XlsxCommand>>;

/** An asynchronous Xlsx session. File I/O and platform resources belong to the caller. */
export class XlsxWorkerSession {
  protected constructor(
    private readonly connection: Connection<XlsxOperation, XlsxInputLimits>,
  ) {}

  static async open(
    engine: EngineHandle,
    workerUrl: URL,
    signal?: AbortSignal,
  ): Promise<XlsxWorkerSession> {
    return new XlsxWorkerSession(await this.connect(engine, workerUrl, signal));
  }

  protected static connect(
    engine: EngineHandle,
    workerUrl: URL,
    signal?: AbortSignal,
  ) {
    return openWorkerConnection<XlsxOperation, XlsxInputLimits>(
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

  inputLimits(): XlsxInputLimits {
    return this.connection.inputLimits();
  }

  protected checkCommand(command: XlsxCommand): void {
    checkXlsxByteInput(command, this.inputLimits());
  }

  async execute<C extends XlsxCommand>(command: C): Promise<XlsxResult<C>> {
    this.checkCommand(command);
    const request =
      command.operation === "openXlsx" ||
      command.operation === "createXlsx" ||
      command.operation === "importXlsxDelimited" ||
      command.operation === "editXlsxSheet"
        ? { ...command, date: spreadsheetDate(command.date) }
        : command;
    return decodeXlsxResult(command, await this.connection.request(request));
  }

  dispose(): void {
    this.connection.dispose();
  }
}
