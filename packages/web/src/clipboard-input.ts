/** Uses native paste data and one queued asynchronous copy/cut path. */
export function bindClipboard(
  input: HTMLTextAreaElement,
  signal: AbortSignal,
  copy: (cut: boolean) => void,
  paste: (text: string) => void,
  reject: (error: Error) => void,
  composing: () => boolean,
): void {
  const options = { signal };
  for (const type of ["copy", "cut"] as const)
    input.addEventListener(
      type,
      (event) => {
        event.preventDefault();
        if (composing() || event.cancelable) copy(type === "cut");
        else reject(new Error("Clipboard event cannot be cancelled"));
      },
      options,
    );
  input.addEventListener(
    "keydown",
    (event) => {
      if (event.isComposing || composing()) return;
      const key = event.key.toLowerCase();
      if (
        (event.ctrlKey || event.metaKey) &&
        !event.altKey &&
        !event.shiftKey &&
        (key === "c" || key === "x")
      ) {
        event.preventDefault();
        copy(key === "x");
      } else if (
        key === "insert" &&
        event.ctrlKey &&
        !event.shiftKey &&
        !event.altKey
      ) {
        event.preventDefault();
        copy(false);
      } else if (
        key === "delete" &&
        event.shiftKey &&
        !event.ctrlKey &&
        !event.metaKey &&
        !event.altKey
      ) {
        event.preventDefault();
        copy(true);
      }
    },
    options,
  );
  input.addEventListener(
    "paste",
    (event) => {
      event.preventDefault();
      if (composing()) {
        paste("");
        return;
      }
      const data = event.clipboardData;
      if (
        !event.cancelable ||
        !data ||
        (data.types.length > 0 && !data.types.includes("text/plain"))
      ) {
        reject(new Error("Paste requires readable plain text"));
        return;
      }
      paste(data.getData("text/plain"));
    },
    options,
  );
}
