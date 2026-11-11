import { OfficeSession, DocumentError } from "@open-document/wasm/abi/session";
import { checkDocxByteInput, type DocxInputLimits } from "./docx-input.js";
import {
  docxCommands,
  type DocxCommand,
  type DocxResult,
} from "./docx-command.js";

export interface DocxRuntime {
  inputLimits(): DocxInputLimits;
  call<T = unknown>(request: object): T;
  bytes(request: Record<string, unknown>): Uint8Array;
  outputBytes(slot: number): Uint8Array;
  setRecording(enabled: boolean): void;
}

/** One document owns its core state and tracking clock. Handlers have no state. */
export class FoundationSession extends OfficeSession<DocxInputLimits> {
  private recording = false;
  private readonly runtime: DocxRuntime = {
    inputLimits: () => this.inputLimits(),
    call: <T>(request: object) => this.call<T>(request),
    bytes: (request) => this.bytes(request),
    outputBytes: (slot) => this.outputBytes(slot),
    setRecording: (enabled) => {
      this.recording = enabled;
    },
  };

  constructor(exports: WebAssembly.Exports, handle: unknown) {
    super(exports, handle, "docx");
  }

  protected override call<T = unknown>(request: object): T {
    return super.call<T>(
      this.recording
        ? { ...request, trackingDate: new Date().toISOString() }
        : request,
    );
  }

  execute<C extends DocxCommand>(command: C): DocxResult<C> {
    if (!Object.hasOwn(docxCommands, command.operation))
      throw new DocumentError(
        "invalid-operation",
        "Unknown DOCX command",
        "",
        -1,
      );
    if (
      command.operation === "rasterHeaderDocx" ||
      command.operation === "addImage" ||
      (command.operation === "editPicture" && "bytes" in command.picture) ||
      (command.operation === "setWatermark" &&
        command.value?.kind === "picture" &&
        command.value.image instanceof Uint8Array)
    )
      checkDocxByteInput(command, this.inputLimits());
    const handler = docxCommands[command.operation] as (
      runtime: DocxRuntime,
      command: C,
    ) => DocxResult<C>;
    return handler(this.runtime, command);
  }
}
