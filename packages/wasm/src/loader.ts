export interface EngineSource {
  readonly url: URL;
  readonly build: string;
}

declare const engineBrand: unique symbol;
/** An immutable compiled engine; each document creates its own Instance. */
export interface EngineHandle {
  readonly [engineBrand]: true;
}

const modules = new WeakMap<EngineHandle, WebAssembly.Module>();
let current: { key: string; promise: Promise<EngineHandle> } | undefined;

/** Share one in-flight fetch/compile in this realm. Cancellation belongs to each waiter. */
export function loadEngine(
  source: EngineSource,
  signal?: AbortSignal,
): Promise<EngineHandle> {
  signal?.throwIfAborted();
  if (
    !source.build ||
    !["http:", "https:", "file:"].includes(source.url.protocol)
  )
    return Promise.reject(
      new Error("An absolute engine URL and build identity are required"),
    );
  const key = JSON.stringify([source.url.href, source.build]);
  if (current?.key !== key) {
    const entry = { key, promise: compile(source) };
    current = entry;
    void entry.promise.catch(() => {
      if (current === entry) current = undefined;
    });
  }
  const shared = current.promise;
  if (!signal) return shared;
  return new Promise((resolve, reject) => {
    const abort = () => reject(signal.reason);
    signal.addEventListener("abort", abort, { once: true });
    shared
      .then(resolve, reject)
      .finally(() => signal.removeEventListener("abort", abort));
    if (signal.aborted) abort();
  });
}

async function compile(source: EngineSource): Promise<EngineHandle> {
  const response = await fetch(source.url, { cache: "no-store" });
  if (!response.ok)
    throw new Error(`Engine request failed: ${response.status}`);
  const module = await WebAssembly.compile(await response.arrayBuffer(), {
    builtins: ["js-string"],
    importedStringConstants: "_",
  });
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
  const instance = new WebAssembly.Instance(module, {});
  const version = instance.exports.abi_version;
  const create = instance.exports[`${format}_new`];
  if (
    typeof version !== "function" ||
    version() !== 1 ||
    typeof create !== "function"
  )
    throw new Error("Unsupported engine ABI");
  return { exports: instance.exports, context: create() };
}
