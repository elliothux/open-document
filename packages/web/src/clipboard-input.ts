import type { FoundationClient } from "./foundation.js";
import type { EditState } from "@open-document/wasm/foundation";
import { assertDocxSelection } from "./document-selection.js";
import type { PptxClient } from "./pptx.js";
import type { PptxQuery } from "@open-document/wasm/pptx";

export async function copyPptxSelection(
  client: PptxClient,
  state: PptxQuery,
  cut: boolean,
  profile: Record<string, string>,
): Promise<PptxQuery | undefined> {
  const revision = state.revision,
    selection = { ...state.selection };
  const { text } = await client.execute({ operation: "copyPptx", revision });
  await navigator.clipboard.writeText(text);
  if (!cut) return;
  const current = await client.execute({ operation: "queryPptx" });
  if (
    current.revision !== revision ||
    JSON.stringify(current.selection) !== JSON.stringify(selection)
  )
    throw new Error("Selection changed during clipboard write");
  return client.execute({
    operation: "replacePptx",
    revision,
    text: "",
    profile,
  });
}

export async function copyDocxSelection(
  client: FoundationClient,
  state: EditState,
  cut: boolean,
  assertOpen: () => void,
): Promise<EditState | null> {
  const revision = state.revision,
    selection = state.selection;
  if (!selection) throw new Error("Click a document position first");
  const text = await client.selectedText(revision, selection, cut);
  assertOpen();
  if (text.length === 0) return null;
  if (!navigator.clipboard) throw new Error("Clipboard API is unavailable");
  await navigator.clipboard.writeText(text);
  assertOpen();
  if (!cut) return null;
  const current = await client.editState();
  assertOpen();
  assertDocxSelection(current, revision, selection);
  return client.replaceRange(revision, selection, "");
}

/** Uses native paste data and one queued asynchronous copy/cut path. */
export function bindClipboard(
  input: HTMLElement,
  signal: AbortSignal,
  copy: (cut: boolean) => void,
  paste: (text: string) => void,
  reject: (error: Error) => void,
  composing: () => boolean,
  native: () => boolean = () => false,
): void {
  const options = { signal };
  for (const type of ["copy", "cut"] as const)
    input.addEventListener(
      type,
      (event) => {
        if (native()) return;
        event.preventDefault();
        if (composing() || event.cancelable) copy(type === "cut");
        else reject(new Error("Clipboard event cannot be cancelled"));
      },
      options,
    );
  input.addEventListener(
    "keydown",
    (event) => {
      if (native()) return;
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
      if (native()) return;
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
