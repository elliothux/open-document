import { record, hasFields } from "./validation.js";
import type { Budget } from "./validation.js";

export class DocumentError extends Error {
  constructor(
    readonly code: string,
    message: string,
    readonly part: string,
    readonly offset: number,
  ) {
    super(message);
    this.name = "DocumentError";
  }
}

export function resourceBudget(value: unknown): Budget {
  if (
    !hasFields(
      value,
      [],
      [
        "fileBytes",
        "entryBytes",
        "totalBytes",
        "retainedBytes",
        "entries",
        "xmlDepth",
        "outputBytes",
      ],
    )
  )
    throw new Error("Invalid resource budget returned by Wasm");
  return value as Budget;
}

export function binaryString(bytes: Uint8Array): string {
  let binary = "";
  for (let start = 0; start < bytes.length; start += 32768)
    binary += Reflect.apply(
      String.fromCharCode,
      null,
      bytes.subarray(start, start + 32768),
    ) as string;
  return binary;
}

export function encodeBytes(bytes: Uint8Array): string {
  return btoa(binaryString(bytes));
}

export class WasmSession {
  private closed = false;

  constructor(
    private readonly exports: WebAssembly.Exports,
    private readonly handle: unknown,
    private readonly format: "docx" | "xlsx" | "pptx" | "pdf",
  ) {}

  protected checkOpen(): void {
    if (this.closed) throw new Error("Session is closed");
  }

  protected invoke(name: string, ...args: unknown[]): unknown {
    this.checkOpen();
    const fn = this.exports[name];
    if (typeof fn !== "function") throw new Error(`Missing ${name} export`);
    const output: unknown = fn(this.handle, ...args);
    if (typeof output !== "string") throw new Error("Invalid Wasm response");
    const result = record(JSON.parse(output));
    if (result.ok === true) return result.value;
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

  protected call(request: object): unknown {
    this.checkOpen();
    return this.invoke(`${this.format}_call`, JSON.stringify(request));
  }

  addFont(bytes: Uint8Array, identity: string): void {
    if (bytes.length > 33554432)
      throw new DocumentError(
        "limit-exceeded",
        "Font input exceeds budget",
        "",
        -1,
      );
    this.checkOpen();
    if (typeof identity !== "string")
      throw new DocumentError(
        "invalid-operation",
        "Invalid string field: identity",
        "",
        -1,
      );
    this.invoke(`${this.format}_add_font`, binaryString(bytes), identity);
  }

  protected bytes(request: Record<string, unknown>): Uint8Array {
    const result = record(this.call(request));
    if (typeof result.bytes !== "string")
      throw new Error("Invalid saved bytes");
    return Uint8Array.from(atob(result.bytes), (char) => char.charCodeAt(0));
  }

  close(): void {
    if (this.closed) return;
    const fn = this.exports[`${this.format}_close`];
    if (typeof fn !== "function")
      throw new Error(`Missing ${this.format}_close export`);
    fn(this.handle);
    this.closed = true;
  }
}

export class OfficeSession extends WasmSession {
  defaultBudget(): Budget {
    return resourceBudget(this.call({ operation: "budget" }));
  }
}

export type { Budget } from "./validation.js";
