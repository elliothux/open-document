import { Connection } from "./connection.js";
import type { InputLimits } from "@open-document/wasm/abi/session";
import type { Response } from "./protocol.js";

type IdleWorker = {
  url: string;
  module: WebAssembly.Module;
  worker: Worker;
  ready: Promise<boolean>;
  expired: ReturnType<typeof setTimeout>;
  dead: boolean;
  terminate: () => void;
};

let idle: IdleWorker | undefined;

function releaseWorker(
  worker: Worker,
  id: number,
  url: string,
  module: WebAssembly.Module,
): void {
  idle?.terminate();
  const ready = Promise.withResolvers<boolean>();
  const acknowledgment = setTimeout(() => entry.terminate(), 250);
  const expired = setTimeout(() => entry.terminate(), 15_000);
  const entry: IdleWorker = {
    url,
    module,
    worker,
    ready: ready.promise,
    expired,
    dead: false,
    terminate() {
      if (entry.dead) return;
      entry.dead = true;
      if (idle === entry) idle = undefined;
      clearTimeout(acknowledgment);
      clearTimeout(expired);
      worker.terminate();
      ready.resolve(false);
    },
  };
  idle = entry;
  worker.onmessage = ({ data }: MessageEvent<Response>) => {
    if (data.id !== id || !data.ok || data.value !== null) {
      entry.terminate();
      return;
    }
    clearTimeout(acknowledgment);
    ready.resolve(true);
  };
  worker.onerror = entry.terminate;
  worker.onmessageerror = entry.terminate;
  try {
    worker.postMessage({ id, command: { operation: "release" } });
  } catch {
    entry.terminate();
  }
}

export async function openWorkerConnection<
  Operation extends { operation: string },
  Limits extends InputLimits,
>(
  module: WebAssembly.Module,
  url: URL,
  signal?: AbortSignal,
): Promise<Connection<Operation, Limits>> {
  signal?.throwIfAborted();
  const href = url.href;
  let worker: Worker | undefined;
  const entry = idle;
  if (entry?.module === module && entry.url === href) {
    idle = undefined;
    clearTimeout(entry.expired);
    signal?.addEventListener("abort", entry.terminate, { once: true });
    try {
      if ((await entry.ready) && !entry.dead) worker = entry.worker;
      signal?.throwIfAborted();
    } finally {
      signal?.removeEventListener("abort", entry.terminate);
    }
  }
  const connection = new Connection<Operation, Limits>(
    worker ?? new Worker(href, { type: "module" }),
    (worker, id) => releaseWorker(worker, id, href, module),
  );
  try {
    await connection.initialize(
      worker
        ? { operation: "initialize" }
        : { operation: "initialize", module },
      signal,
    );
    return connection;
  } catch (error) {
    connection.dispose(false);
    throw error;
  }
}
