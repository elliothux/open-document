import { record, hasFields } from "./validation.js";
import type { Budget } from "./validation.js";
import { OutlineDelta } from "./outline-delta.js";

export type DocumentStage =
  | "engine"
  | "worker"
  | "input"
  | "container"
  | "open"
  | "font"
  | "image"
  | "layout"
  | "draw"
  | "save";

export class DocumentError extends Error {
  readonly resource: string | undefined;

  constructor(
    readonly code: string,
    message: string,
    readonly part: string,
    readonly offset: number,
    readonly stage?: DocumentStage,
    options?: ErrorOptions & { readonly resource?: string | undefined },
  ) {
    super(message, options);
    this.name = "DocumentError";
    this.resource = options?.resource;
  }
}

const byteWordDecoder = new TextDecoder(
  new Uint8Array(new Uint16Array([1]).buffer)[0] === 1
    ? "utf-16le"
    : "utf-16be",
);

export function binaryString(bytes: Uint8Array): string {
  const words = new Uint16Array(Math.min(bytes.length, 32768));
  let binary = "";
  // Widen each octet without applying a legacy character encoding.
  for (let start = 0; start < bytes.length; start += words.length) {
    const chunk = bytes.subarray(start, start + words.length);
    words.set(chunk);
    binary += byteWordDecoder.decode(words.subarray(0, chunk.length));
  }
  return binary;
}

export interface InputLimits {
  readonly fontBytes: number;
}

/** Reject host input before encoding or structured cloning. */
export function checkByteInput(
  bytes: unknown,
  ceiling: number,
): asserts bytes is Uint8Array {
  if (!(bytes instanceof Uint8Array))
    throw new DocumentError("invalid-operation", "Invalid byte input", "", -1);
  if (bytes.length > ceiling)
    throw new DocumentError(
      "limit-exceeded",
      "Byte input exceeds budget",
      "",
      -1,
    );
}

/** Apply core limits before allocating a byte string or cloning host input. */
export function checkFontInput(
  bytes: unknown,
  identity: unknown,
  limits: InputLimits,
): void {
  if (!(bytes instanceof Uint8Array))
    throw new DocumentError("invalid-operation", "Invalid byte input", "", -1);
  if (bytes.length > limits.fontBytes)
    throw new DocumentError(
      "limit-exceeded",
      "Font input exceeds budget",
      "",
      -1,
    );
  if (typeof identity !== "string")
    throw new DocumentError(
      "invalid-operation",
      "Invalid string field: identity",
      "",
      -1,
    );
}

export class WasmSession<Limits extends InputLimits = InputLimits> {
  private closed = false;
  private limits: Limits | undefined;
  private readonly outlines = new OutlineDelta();

  constructor(
    private readonly exports: WebAssembly.Exports,
    private readonly handle: unknown,
    private readonly format: "docx" | "xlsx" | "pptx" | "pdf",
  ) {}

  protected checkOpen(): void {
    if (this.closed) throw new Error("Session is closed");
  }

  private invokeRaw(name: string, ...args: unknown[]): unknown {
    this.checkOpen();
    const fn = this.exports[name];
    if (typeof fn !== "function") throw new Error(`Missing ${name} export`);
    return fn(this.handle, ...args);
  }

  protected invoke(name: string, ...args: unknown[]): unknown {
    const output = this.invokeRaw(name, ...args);
    if (typeof output !== "string") throw new Error("Invalid Wasm response");
    const result = record(JSON.parse(output));
    if (result.ok === true) return this.outlines.update(result.value);
    const error = record(result.error);
    if (
      result.ok !== false ||
      !hasFields(error, ["code", "message", "part"], ["offset"])
    )
      throw new Error("Invalid Wasm error");
    if (
      typeof error.code === "string" &&
      typeof error.message === "string" &&
      typeof error.part === "string" &&
      typeof error.offset === "number"
    )
      throw new DocumentError(
        error.code,
        error.message,
        error.part,
        error.offset,
      );
    throw new Error("Invalid Wasm error");
  }

  protected call<T = unknown>(request: object): T {
    this.checkOpen();
    const attachments: Uint8Array[] = [];
    const input = JSON.stringify(
      request,
      function (this: object, key, value: unknown) {
        // JSON calls Buffer.toJSON before the replacer receives its value.
        const bytes: unknown =
          value !== null &&
          typeof value === "object" &&
          !(value instanceof Uint8Array)
            ? Object.getOwnPropertyDescriptor(this, key)?.value
            : value;
        if (!(bytes instanceof Uint8Array)) return value;
        if (!bytes.length) return "";
        if (attachments.length === 2)
          throw new DocumentError(
            "invalid-operation",
            "Too many byte attachments",
            "",
            -1,
          );
        const index = attachments.length;
        attachments.push(bytes);
        return { $bytes: index };
      },
    );
    const [first, second] = attachments;
    return this.invoke(
      `${this.format}_call`,
      input,
      first ? binaryString(first) : "",
      second ? binaryString(second) : "",
    ) as T;
  }

  inputLimits(): Limits {
    this.checkOpen();
    return (this.limits ??= Object.freeze(
      this.call<Limits>({ operation: "inputLimits" }),
    ));
  }

  addFont(bytes: Uint8Array, identity: string): void {
    checkFontInput(bytes, identity, this.inputLimits());
    this.invoke(`${this.format}_add_font`, binaryString(bytes), identity);
  }

  protected bytes(request: Record<string, unknown>): Uint8Array {
    const result = this.call<{ bytes: number }>(request);
    return this.outputBytes(result.bytes);
  }

  protected outputString(slot: number): string {
    if (!Number.isSafeInteger(slot) || slot < 0 || slot > 2147483647)
      throw new Error("Invalid Wasm byte output slot");
    const output = this.invokeRaw(`${this.format}_output`, slot);
    if (typeof output !== "string") throw new Error("Missing Wasm byte output");
    return output;
  }

  protected outputBytes(slot: number): Uint8Array {
    const output = this.outputString(slot);
    const bytes = new Uint8Array(output.length);
    for (let index = 0; index < bytes.length; index++) {
      const byte = output.charCodeAt(index);
      if (byte > 255) throw new Error("Invalid Wasm byte output");
      bytes[index] = byte;
    }
    return bytes;
  }

  close(): void {
    if (this.closed) return;
    const fn = this.exports[`${this.format}_close`];
    if (typeof fn !== "function")
      throw new Error(`Missing ${this.format}_close export`);
    fn(this.handle);
    this.outlines.clear();
    this.closed = true;
  }
}

export class OfficeSession<
  Limits extends InputLimits = InputLimits,
> extends WasmSession<Limits> {
  defaultBudget(): Budget {
    return this.call<Budget>({ operation: "budget" });
  }
}

export type { Budget } from "./validation.js";
