import type { Request, Response } from "./protocol";

type Operation = Request extends infer R
  ? R extends Request
    ? Omit<R, "id">
    : never
  : never;

/** Plain-text POC host. This is not a DOCX/XLSX/PPTX editor. */
export class TextClient {
  private nextId = 0;
  private closed = false;
  private pending:
    | {
        id: number;
        resolve: (text: string) => void;
        reject: (error: Error) => void;
      }
    | undefined;

  private constructor(private readonly worker: Worker) {
    worker.onmessage = (event: MessageEvent<Response>) => {
      const response = event.data;
      const pending = this.pending;
      if (!pending || response.id !== pending.id) return;
      this.pending = undefined;
      if (response.ok) pending.resolve(response.text);
      else pending.reject(new Error(response.error));
    };
    worker.onerror = (event) => {
      this.pending?.reject(new Error(event.message));
      this.pending = undefined;
      this.dispose();
    };
    worker.onmessageerror = () => {
      this.pending?.reject(new Error("Worker message could not be decoded"));
      this.pending = undefined;
      this.dispose();
    };
  }

  static async open(
    text: string,
    wasm: ArrayBuffer,
    workerUrl: URL,
  ): Promise<TextClient> {
    const client = new TextClient(new Worker(workerUrl, { type: "module" }));
    try {
      await client.request({ operation: "open", text, wasm });
      return client;
    } catch (error) {
      client.dispose();
      throw error;
    }
  }

  private request(operation: Operation): Promise<string> {
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

  read(): Promise<string> {
    return this.request({ operation: "read" });
  }

  replace(start: number, end: number, text: string): Promise<string> {
    return this.request({ operation: "replace", start, end, text });
  }

  undo(): Promise<string> {
    return this.request({ operation: "undo" });
  }

  dispose(): void {
    if (this.closed) return;
    this.closed = true;
    this.pending?.reject(new Error("Client is closed"));
    this.pending = undefined;
    this.worker.terminate();
  }
}
