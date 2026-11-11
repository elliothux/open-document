import type { Response, WorkerInitialization } from "./protocol.js";
export type { WorkerInitialization } from "./protocol.js";
import { DocumentError, checkFontInput } from "@open-document/wasm/abi/session";
import { OutlineDelta } from "@open-document/wasm/abi/outline-delta";
import type {
  DocumentStage,
  InputLimits,
} from "@open-document/wasm/abi/session";

export function documentFailure(
  stage: DocumentStage,
  cause: unknown,
  resource?: string,
): Error {
  if (
    (cause instanceof DocumentError && cause.stage) ||
    (cause instanceof DOMException &&
      (cause.name === "AbortError" || "stage" in cause))
  )
    return cause;
  const error = cause instanceof DocumentError ? cause : undefined;
  if (
    stage === "open" &&
    (error?.code === "malformed-package" ||
      error?.code === "unsupported-package")
  )
    stage = "container";
  const message = `Document ${stage} failed${resource ? ` (${resource})` : ""}: ${cause instanceof Error ? cause.message : String(cause)}`;
  if (cause instanceof DOMException)
    return Object.assign(new DOMException(message, cause.name), {
      stage,
      resource,
      cause,
    });
  return new DocumentError(
    error?.code ?? "host-error",
    message,
    error?.part ?? "",
    error?.offset ?? -1,
    stage,
    { cause, resource },
  );
}

export async function registerFonts(
  connection: {
    addFont(bytes: Uint8Array, identity: string): Promise<unknown>;
  },
  fonts: readonly { readonly identity: string; readonly bytes: Uint8Array }[],
  signal: AbortSignal,
): Promise<void> {
  for (const font of fonts) {
    signal.throwIfAborted();
    try {
      await connection.addFont(font.bytes, font.identity);
    } catch (cause) {
      signal.throwIfAborted();
      throw documentFailure("font", cause, font.identity);
    }
  }
}

/** One worker owner with one in-flight operation. Disposal cancels pending work. */
export class Connection<
  Operation extends { operation: string },
  Limits extends InputLimits = InputLimits,
> {
  private nextId = 0;
  private closed = false;
  private reusable = false;
  private limits: Limits | undefined;
  private readonly outlines = new OutlineDelta();
  private pending:
    | {
        id: number;
        resolve: (value: unknown) => void;
        reject: (error: Error) => void;
      }
    | undefined;

  constructor(
    private readonly worker: Worker,
    private readonly release?: (worker: Worker, id: number) => void,
  ) {
    worker.onmessage = (event: MessageEvent<Response>) => {
      const response = event.data;
      const pending = this.pending;
      if (!pending || response.id !== pending.id) return;
      this.pending = undefined;
      if (response.ok) {
        if (response.reusable) this.reusable = true;
        try {
          pending.resolve(this.outlines.update(response.value));
        } catch (error) {
          pending.reject(
            error instanceof Error ? error : new Error(String(error)),
          );
          this.dispose(false);
        }
      } else
        pending.reject(
          response.code
            ? new DocumentError(
                response.code,
                response.error,
                response.part ?? "",
                response.offset ?? -1,
              )
            : new Error(response.error),
        );
    };
    worker.onerror = (event) =>
      this.fail(
        new Error(
          event.message ||
            "Worker script could not load or stopped unexpectedly",
        ),
      );
    worker.onmessageerror = () =>
      this.fail(new Error("Worker message could not be decoded"));
  }

  private fail(error: Error): void {
    this.pending?.reject(error);
    this.pending = undefined;
    this.dispose(false);
  }

  inputLimits(): Limits {
    if (this.closed) throw new Error("Client is closed");
    if (!this.limits) throw new Error("Session is not open");
    return this.limits;
  }

  request(operation: Operation | WorkerInitialization): Promise<unknown> {
    if (this.closed) return Promise.reject(new Error("Client is closed"));
    if (this.pending)
      return Promise.reject(new Error("Await the previous operation"));
    if (operation.operation === "font") {
      try {
        checkFontInput(
          "bytes" in operation ? operation.bytes : undefined,
          "identity" in operation ? operation.identity : undefined,
          this.inputLimits(),
        );
      } catch (error) {
        return Promise.reject(error);
      }
    }
    const id = this.nextId++;
    return new Promise((resolve, reject) => {
      this.pending = { id, resolve, reject };
      try {
        this.worker.postMessage({ id, command: operation });
      } catch (error) {
        this.pending = undefined;
        this.dispose(false);
        reject(error);
      }
    });
  }

  async initialize(
    operation: Operation | WorkerInitialization,
    signal?: AbortSignal,
  ): Promise<void> {
    signal?.throwIfAborted();
    const abort = () => this.dispose(false);
    signal?.addEventListener("abort", abort, { once: true });
    try {
      const limits = (await this.request(operation)) as Limits;
      signal?.throwIfAborted();
      this.limits = Object.freeze(limits);
    } catch (error) {
      signal?.throwIfAborted();
      throw error;
    } finally {
      signal?.removeEventListener("abort", abort);
    }
  }

  dispose(recycle = true): void {
    if (this.closed) return;
    this.closed = true;
    const idle = !this.pending;
    this.pending?.reject(new Error("Client is closed"));
    this.pending = undefined;
    this.outlines.clear();
    if (recycle && idle && this.limits && this.reusable && this.release)
      this.release(this.worker, this.nextId);
    else this.worker.terminate();
  }
}
