/** Browser ABI adapter. Document state lives only in WasmGC. */
export class TextSession {
  private closed = false;

  constructor(
    private readonly exports: WebAssembly.Exports,
    private readonly handle: unknown,
  ) {}

  private invoke(name: string, ...args: unknown[]): unknown {
    if (this.closed) throw new Error("Session is closed");
    const fn = this.exports[name];
    if (typeof fn !== "function")
      throw new Error(`Missing Wasm export: ${name}`);
    return fn(this.handle, ...args);
  }

  read(): string {
    const text = this.invoke("read_text");
    if (typeof text !== "string")
      throw new Error("Invalid text returned by Wasm");
    return text;
  }

  replace(start: number, end: number, replacement: string): void {
    // JS numbers must not silently wrap when converted to Wasm i32.
    for (const offset of [start, end]) {
      if (!Number.isInteger(offset) || offset < 0 || offset > 0x7fffffff) {
        throw new RangeError("Offsets must be non-negative i32 values");
      }
    }
    const status = this.invoke("replace_text", start, end, replacement);
    if (status !== 0)
      throw new Error(`Text replacement failed: ${String(status)}`);
  }

  undo(): void {
    const status = this.invoke("undo");
    if (status !== 0) throw new Error(`Undo failed: ${String(status)}`);
  }

  close(): void {
    if (this.closed) return;
    this.invoke("close");
    this.closed = true;
  }
}

export async function loadEngine(wasm: BufferSource): Promise<{
  openText(text: string): TextSession;
}> {
  const { instance } = await WebAssembly.instantiate(
    wasm,
    {},
    {
      builtins: ["js-string"],
      importedStringConstants: "_",
    },
  );
  const open = instance.exports.open_text;
  if (typeof open !== "function")
    throw new Error("Missing Wasm export: open_text");
  return {
    openText(text) {
      return new TextSession(instance.exports, open(text));
    },
  };
}
