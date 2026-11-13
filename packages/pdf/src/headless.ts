import type { EngineHandle } from "@open-document/wasm";
import { engineModule } from "@open-document/wasm/loader";
import type { Connection } from "@open-document/web-core/connection";
import { openWorkerConnection } from "@open-document/web-core/worker-connection";
import type { WorkerOperation } from "@open-document/web-core/protocol";
import { type PdfCommand, type PdfQuery, type PdfResult } from "./core/pdf.js";
import {
  checkPdfByteInput,
  type PdfInputLimits,
  type PdfBudget,
} from "./core/pdf.js";
export type { PdfCommand, PdfResult } from "./core/pdf.js";

export type PdfFileCommand =
  | { operation: "pdfFileBudget" }
  | { operation: "openPdfFile"; file: Blob; budget?: PdfBudget };

type Operation = WorkerOperation<PdfCommand | PdfFileCommand>;

/** An asynchronous PDF session with bytes and Blob input. */
export class PdfWorkerSession {
  protected constructor(
    private readonly connection: Connection<Operation, PdfInputLimits>,
  ) {}

  static async open(
    engine: EngineHandle,
    workerUrl: URL,
    signal?: AbortSignal,
  ): Promise<PdfWorkerSession> {
    return new PdfWorkerSession(await this.connect(engine, workerUrl, signal));
  }

  protected static connect(
    engine: EngineHandle,
    workerUrl: URL,
    signal?: AbortSignal,
  ) {
    return openWorkerConnection<Operation, PdfInputLimits>(
      engineModule(engine),
      workerUrl,
      signal,
    );
  }

  async defaultBudget(): Promise<PdfBudget> {
    return this.execute({ operation: "defaultPdfBudget" });
  }

  async defaultFileBudget(): Promise<PdfBudget> {
    return (await this.connection.request({
      operation: "pdfFileBudget",
    })) as PdfBudget;
  }

  /** Open a read-only PDF by requesting only the required file ranges. */
  async openFile(file: Blob, budget?: PdfBudget): Promise<PdfQuery> {
    return (await this.connection.request({
      operation: "openPdfFile",
      file,
      ...(budget === undefined ? {} : { budget }),
    })) as PdfQuery;
  }

  async addFont(bytes: Uint8Array, identity: string): Promise<void> {
    await this.connection.request({ operation: "font", bytes, identity });
  }

  inputLimits(): PdfInputLimits {
    return this.connection.inputLimits();
  }

  protected checkCommand(command: PdfCommand): void {
    checkPdfByteInput(command, this.inputLimits());
  }

  async execute<C extends PdfCommand>(command: C): Promise<PdfResult<C>> {
    this.checkCommand(command);
    return (await this.connection.request(command)) as PdfResult<C>;
  }

  dispose(): void {
    this.connection.dispose();
  }
}
