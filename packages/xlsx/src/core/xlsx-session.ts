import { OfficeSession, DocumentError } from "@open-document/wasm/abi/session";
import { checkXlsxByteInput, type XlsxInputLimits } from "./xlsx.js";
import {
  xlsxCommands,
  decodeXlsxResult,
  type XlsxCommand,
  type XlsxResult,
} from "./xlsx-command.js";

export interface XlsxRuntime {
  call<T = unknown>(request: object): T;
  bytes(request: Record<string, unknown>): Uint8Array;
  outputBytes(slot: number): Uint8Array;
}

/** One workbook owns its MoonBit session; command handlers have no state. */
export class XlsxSession extends OfficeSession<XlsxInputLimits> {
  private readonly runtime: XlsxRuntime = {
    call: <T>(request: object) => this.call<T>(request),
    bytes: (request) => this.bytes(request),
    outputBytes: (slot) => this.outputBytes(slot),
  };

  constructor(exports: WebAssembly.Exports, handle: unknown) {
    super(exports, handle, "xlsx");
  }

  execute<C extends XlsxCommand>(command: C): XlsxResult<C> {
    return decodeXlsxResult(command, this.executeWire(command));
  }

  /** Keep compact viewport responses in the Worker until the client reads them. */
  executeWire<C extends XlsxCommand>(command: C): unknown {
    if (!Object.hasOwn(xlsxCommands, command.operation))
      throw new DocumentError(
        "invalid-operation",
        "Unknown XLSX command",
        "",
        -1,
      );
    if (
      "bytes" in command ||
      command.operation === "drawingFragmentImageXlsx" ||
      command.operation === "pasteDrawingXlsx"
    )
      checkXlsxByteInput(command, this.inputLimits());
    const handler = xlsxCommands[command.operation] as (
      runtime: XlsxRuntime,
      command: C,
    ) => unknown;
    return handler(this.runtime, command);
  }
}
