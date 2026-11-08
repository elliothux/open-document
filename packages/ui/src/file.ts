import { documentFailure } from "@open-document/web-core/connection";
import { DocumentError } from "@open-document/wasm/abi/session";

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
  return promise
    .catch((error: unknown) => {
      signal.throwIfAborted();
      throw documentFailure("input", error);
    })
    .finally(() => {
      signal.removeEventListener("abort", abort);
      reader.onload = reader.onerror = reader.onabort = null;
    });
}

export async function openWithPassword(
  parent: HTMLElement,
  format: "PDF" | "DOCX",
  chinese: boolean,
  signal: AbortSignal,
  open: (password: string | undefined) => Promise<unknown>,
): Promise<void> {
  let password: string | undefined;
  for (;;) {
    signal.throwIfAborted();
    try {
      await open(password);
      return;
    } catch (error) {
      if (
        !(error instanceof DocumentError) ||
        error.code !== `${format.toLowerCase()}-password-required`
      )
        throw error;
      password = await filePassword(
        parent,
        format,
        chinese,
        password !== undefined,
        signal,
      );
    }
  }
}

function filePassword(
  parent: HTMLElement,
  format: "PDF" | "DOCX",
  chinese: boolean,
  retry: boolean,
  signal: AbortSignal,
): Promise<string> {
  signal.throwIfAborted();
  const document = parent.ownerDocument;
  const dialog = document.createElement("dialog");
  const form = document.createElement("form");
  const title = document.createElement("p");
  title.textContent = chinese ? `解锁 ${format}` : `Unlock ${format}`;
  dialog.setAttribute("aria-label", title.textContent);
  form.append(title);
  if (retry) {
    const error = document.createElement("p");
    error.setAttribute("role", "alert");
    error.textContent = chinese
      ? "密码不正确，请重试。"
      : "Incorrect password. Try again.";
    form.append(error);
  }
  const label = document.createElement("label");
  label.textContent = chinese ? "密码 " : "Password ";
  const input = document.createElement("input");
  input.type = "password";
  input.autofocus = true;
  input.autocomplete = "off";
  input.maxLength = format === "PDF" ? 127 : 255;
  label.append(input);
  const submit = document.createElement("button");
  submit.textContent = chinese ? "解锁" : "Unlock";
  const cancel = document.createElement("button");
  cancel.type = "button";
  cancel.textContent = chinese ? "取消" : "Cancel";
  form.append(label, submit, cancel);
  dialog.append(form);
  parent.append(dialog);
  return new Promise((resolve, reject) => {
    const cleanup = () => {
      signal.removeEventListener("abort", abort);
      input.value = "";
      dialog.close();
      dialog.remove();
    };
    const abort = () => {
      cleanup();
      reject(new DOMException("Opening cancelled", "AbortError"));
    };
    form.onsubmit = (event) => {
      event.preventDefault();
      const password = input.value;
      cleanup();
      resolve(password);
    };
    cancel.onclick = abort;
    dialog.oncancel = (event) => {
      event.preventDefault();
      abort();
    };
    signal.addEventListener("abort", abort, { once: true });
    try {
      dialog.showModal();
    } catch (error) {
      cleanup();
      reject(error);
    }
  });
}
