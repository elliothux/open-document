export interface EngineSource {
  readonly url: URL;
  readonly build: string;
}

export type EngineInput = EngineSource | Uint8Array | WebAssembly.Module;

declare const engineBrand: unique symbol;
/** An immutable compiled engine; each document owns its context. */
export interface EngineHandle {
  readonly [engineBrand]: true;
}

const modules = new WeakMap<EngineHandle, WebAssembly.Module>();
const instances = new WeakMap<WebAssembly.Module, WebAssembly.Instance>();
const engines = new Map<string, Promise<EngineHandle>>();

/** Share fetch/compile per engine source. Cancellation belongs to each waiter. */
export function loadEngine(
  source: EngineInput,
  signal?: AbortSignal,
): Promise<EngineHandle> {
  signal?.throwIfAborted();
  if (source instanceof WebAssembly.Module)
    return Promise.resolve()
      .then(() => engineHandle(source))
      .catch((cause: unknown) => {
        throw engineFailure(cause);
      });
  if (source instanceof Uint8Array)
    return waitForEngine(
      compileBytes(source).catch((cause: unknown) => {
        throw engineFailure(cause);
      }),
      signal,
    );
  if (
    !source.build ||
    !["http:", "https:", "file:"].includes(source.url.protocol)
  )
    return Promise.reject(
      new Error("An absolute engine URL and build identity are required"),
    );
  const key = JSON.stringify([source.url.href, source.build]);
  let shared = engines.get(key);
  if (!shared) {
    const pending = compile(source);
    engines.set(key, pending);
    // The combined engine and four format engines fit in one realm.
    if (engines.size > 5) engines.delete(engines.keys().next().value!);
    void pending.catch(() => {
      if (engines.get(key) === pending) engines.delete(key);
    });
    shared = pending;
  }
  return waitForEngine(shared, signal);
}

function waitForEngine(
  pending: Promise<EngineHandle>,
  signal?: AbortSignal,
): Promise<EngineHandle> {
  if (!signal) return pending;
  return new Promise((resolve, reject) => {
    const abort = () => reject(signal.reason);
    signal.addEventListener("abort", abort, { once: true });
    pending
      .then(resolve, reject)
      .finally(() => signal.removeEventListener("abort", abort));
    if (signal.aborted) abort();
  });
}

async function compile(source: EngineSource): Promise<EngineHandle> {
  try {
    const response = await fetch(source.url, { cache: "no-store" });
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    return await compileBytes(await response.arrayBuffer());
  } catch (cause) {
    throw engineFailure(cause, source.url.href);
  }
}

function engineFailure(cause: unknown, resource?: string): DocumentError {
  const reason = cause instanceof Error ? cause.message : String(cause);
  return new DocumentError(
    "engine-load",
    `Cannot load Wasm engine${resource ? ` from ${resource}` : ""}: ${reason}`,
    "",
    -1,
    "engine",
    { cause, resource },
  );
}

async function compileBytes(
  bytes: ArrayBuffer | Uint8Array,
): Promise<EngineHandle> {
  const input = bytes instanceof Uint8Array ? new Uint8Array(bytes) : bytes;
  return engineHandle(
    await WebAssembly.compile(input, {
      builtins: ["js-string"],
      importedStringConstants: "_",
    }),
  );
}

function engineHandle(module: WebAssembly.Module): EngineHandle {
  if (
    !WebAssembly.Module.exports(module).some(
      (entry) => entry.name === "abi_version" && entry.kind === "function",
    )
  )
    throw new Error("Missing engine ABI export");
  const handle = Object.freeze({}) as EngineHandle;
  modules.set(handle, module);
  return handle;
}

/** Worker initialization clones this Module without transferring or recompiling it. */
export function engineModule(handle: EngineHandle): WebAssembly.Module {
  const module = modules.get(handle);
  if (!module) throw new Error("Invalid engine handle");
  return module;
}

export function instantiateEngine(
  module: WebAssembly.Module,
  format: "docx" | "xlsx" | "pptx" | "pdf",
): { exports: WebAssembly.Exports; context: unknown } {
  for (const name of [
    "abi_version",
    `${format}_new`,
    `${format}_call`,
    `${format}_output`,
    `${format}_add_font`,
    `${format}_close`,
  ]) {
    if (
      !WebAssembly.Module.exports(module).some(
        (entry) => entry.name === name && entry.kind === "function",
      )
    )
      throw new Error(`Missing ${name} export`);
  }
  const instance =
    instances.get(module) ?? new WebAssembly.Instance(module, {});
  const version = instance.exports.abi_version;
  const create = instance.exports[`${format}_new`];
  if (
    typeof version !== "function" ||
    version() !== 18 ||
    typeof create !== "function"
  )
    throw new Error("Unsupported engine ABI");
  instances.set(module, instance);
  return { exports: instance.exports, context: create() };
}
import { DocumentError } from "./abi/session.js";
