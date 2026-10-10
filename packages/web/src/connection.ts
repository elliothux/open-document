import type { Operation, Response } from "./protocol";
import { DocumentError } from "@open-document/wasm/foundation";

/** One worker owner with one in-flight operation. Disposal cancels pending work. */
export class Connection {
  private nextId = 0;
  private closed = false;
  private pending:
    | {
        id: number;
        resolve: (value: unknown) => void;
        reject: (error: Error) => void;
      }
    | undefined;

  constructor(private readonly worker: Worker) {
    worker.onmessage = (event: MessageEvent<Response>) => {
      const response = event.data;
      const pending = this.pending;
      if (!pending || response.id !== pending.id) return;
      this.pending = undefined;
      if (response.ok) pending.resolve(response.value);
      else
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
    worker.onerror = (event) => this.fail(new Error(event.message));
    worker.onmessageerror = () =>
      this.fail(new Error("Worker message could not be decoded"));
  }

  private fail(error: Error): void {
    this.pending?.reject(error);
    this.pending = undefined;
    this.dispose();
  }

  request(operation: Operation): Promise<unknown> {
    if (this.closed) return Promise.reject(new Error("Client is closed"));
    if (this.pending)
      return Promise.reject(new Error("Await the previous operation"));
    const id = this.nextId++;
    return new Promise((resolve, reject) => {
      this.pending = { id, resolve, reject };
      try {
        this.worker.postMessage({ ...operation, id });
      } catch (error) {
        this.pending = undefined;
        reject(error);
      }
    });
  }

  dispose(): void {
    if (this.closed) return;
    this.closed = true;
    this.pending?.reject(new Error("Client is closed"));
    this.pending = undefined;
    this.worker.terminate();
  }
}
