/** FileReader supplies cancellation before a candidate Worker exists. */
export function readFile(file: File, signal: AbortSignal): Promise<Uint8Array> {
  signal.throwIfAborted();
  const reader = new FileReader();
  const { promise, resolve, reject } = Promise.withResolvers<Uint8Array>();
  const abort = () => {
    reader.abort();
    reject(signal.reason);
  };
  reader.onload = () => {
    if (reader.result instanceof ArrayBuffer)
      resolve(new Uint8Array(reader.result));
    else reject(new Error("File did not produce binary data"));
  };
  reader.onerror = () =>
    reject(reader.error ?? new Error("File reading failed"));
  reader.onabort = () =>
    reject(
      signal.reason ?? new DOMException("Opening cancelled", "AbortError"),
    );
  signal.addEventListener("abort", abort, { once: true });
  try {
    if (signal.aborted) abort();
    else reader.readAsArrayBuffer(file);
  } catch (error) {
    reject(error);
  }
  return promise.finally(() => {
    signal.removeEventListener("abort", abort);
    reader.onload = reader.onerror = reader.onabort = null;
  });
}
