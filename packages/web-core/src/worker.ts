import {
  errorResponse,
  type Request,
  type Response,
  type WorkerControl,
  type WorkerOperation,
} from "./protocol.js";
import { OutlineDelta } from "@open-document/wasm/abi/outline-delta";

type SessionLifecycle = {
  inputLimits(): unknown;
  addFont(bytes: Uint8Array, identity: string): void;
  close(): void;
};

export class WorkerDocument<
  Session extends { inputLimits(): unknown; close(): void },
> {
  private module: WebAssembly.Module | undefined;
  private current: Session | undefined;

  constructor(
    private readonly instantiate: (module: WebAssembly.Module) => Session,
  ) {}

  initialize(module?: WebAssembly.Module): unknown {
    if (this.current) throw new Error("Session is already open");
    const engine = module ?? this.module;
    if (!engine) throw new Error("Missing engine module");
    this.current = this.instantiate(engine);
    this.module = engine;
    return this.current.inputLimits();
  }

  session(): Session {
    if (!this.current) throw new Error("Session is not open");
    return this.current;
  }

  release(): void {
    this.current?.close();
    this.current = undefined;
  }
}

function isWorkerControl<Command extends { operation: string }>(
  request: WorkerOperation<Command>,
): request is WorkerControl {
  return request.operation === "initialize" || request.operation === "font";
}

export function serveDocument<
  Session extends SessionLifecycle,
  Command extends { operation: string },
>(
  instantiate: (module: WebAssembly.Module) => Session,
  execute: (session: Session, command: Command) => unknown,
): void {
  const document = new WorkerDocument(instantiate);
  serveWorker<WorkerOperation<Command>>(
    async (request) => {
      if (isWorkerControl(request)) {
        if (request.operation === "initialize")
          return document.initialize(request.module);
        document.session().addFont(request.bytes, request.identity);
        return null;
      }
      return execute(document.session(), request);
    },
    () => document.release(),
  );
}

function transferableOutput(operation: string): boolean {
  return (
    operation.startsWith("save") ||
    operation.startsWith("export") ||
    operation === "convertPdfOffice" ||
    operation === "rasterHeaderPdf" ||
    operation === "markupImages" ||
    operation === "tableFragmentImages" ||
    operation === "bodyFragmentImages" ||
    operation === "pictureResourceXlsx" ||
    operation === "inspectPptxSlides" ||
    operation === "objectFragmentResourcesPptx" ||
    operation === "extractPdfPages" ||
    operation === "splitPdfFiles"
  );
}

function fileBuffers(value: unknown): ArrayBuffer[] {
  const buffers = new Set<ArrayBuffer>();
  const add = (output: unknown) => {
    const bytes =
      output !== null && typeof output === "object" && "bytes" in output
        ? output.bytes
        : output;
    if (
      bytes instanceof Uint8Array &&
      bytes.buffer instanceof ArrayBuffer &&
      bytes.byteOffset === 0 &&
      bytes.byteLength === bytes.buffer.byteLength
    ) {
      buffers.add(bytes.buffer);
    }
  };
  add(value);
  if (value !== null && typeof value === "object") {
    if ("files" in value && Array.isArray(value.files))
      for (const file of value.files) add(file);
    if ("images" in value && Array.isArray(value.images))
      for (const image of value.images) add(image);
    if ("media" in value && Array.isArray(value.media))
      for (const clip of value.media) add(clip);
  }
  return [...buffers];
}

/** One ordered dispatch queue per document Worker. */
export function serveWorker<Operation extends { operation: string }>(
  dispatch: (request: Operation) => Promise<unknown>,
  release?: () => void,
): void {
  let busy = false;
  const outlines = new OutlineDelta();
  globalThis.onmessage = async (event: MessageEvent<Request<Operation>>) => {
    const request = event.data;
    if (busy) {
      globalThis.postMessage({
        id: request.id,
        ok: false,
        error: "Await the previous operation",
      });
      return;
    }
    busy = true;
    let response: Response;
    try {
      let value: unknown;
      if (release && request.command.operation === "release") {
        release();
        outlines.clear();
        value = null;
      } else {
        value = outlines.update(await dispatch(request.command), true);
      }
      response = {
        id: request.id,
        ok: true,
        value,
        ...(release && request.command.operation === "initialize"
          ? { reusable: true as const }
          : {}),
      };
    } catch (error) {
      response = errorResponse(request.id, error);
    } finally {
      busy = false;
    }
    if (response.ok && transferableOutput(request.command.operation)) {
      // These buffers are newly allocated for the response.
      const transfer = fileBuffers(response.value);
      if (transfer.length > 0) {
        globalThis.postMessage(response, { transfer });
        return;
      }
    }
    globalThis.postMessage(response);
  };
}
