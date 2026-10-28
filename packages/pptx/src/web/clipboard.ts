import type { PptxClient } from "./pptx.js";
import type { PptxQuery } from "../core/pptx.js";
const pptxTextMime = "web application/x-open-document-pptx-text";
const pptxObjectsMime = "web application/x-open-document-pptx-objects";

export async function copyPptxSelection(
  client: PptxClient,
  state: PptxQuery,
  cut: boolean,
  profile: Record<string, string>,
  assertOpen: () => void,
): Promise<PptxQuery | undefined> {
  const revision = state.revision,
    selection = { ...state.selection };
  const { text, fragment } = await client.execute({
    operation: "copyPptx",
    revision,
  });
  assertOpen();
  if (fragment !== null) {
    const mime = selection.mode === "object" ? pptxObjectsMime : pptxTextMime;
    await navigator.clipboard.write([
      new ClipboardItem({
        "text/plain": new Blob([text], { type: "text/plain" }),
        [mime]: new Blob([fragment], { type: mime.slice(4) }),
      }),
    ]);
  } else await navigator.clipboard.writeText(text);
  assertOpen();
  if (!cut) return;
  const current = await client.execute({ operation: "queryPptx" });
  assertOpen();
  if (
    current.revision !== revision ||
    JSON.stringify(current.selection) !== JSON.stringify(selection)
  )
    throw new Error("Selection changed during clipboard write");
  return client.execute(
    selection.mode === "object"
      ? {
          operation: "editPptxObjects",
          revision,
          change: { action: "delete" },
          profile,
        }
      : { operation: "replacePptx", revision, text: "", profile },
  );
}

/** Reads an independent native text snapshot, with plain text for other applications. */
export async function pastePptxSelection(
  client: PptxClient,
  state: PptxQuery,
  profile: Record<string, string>,
  assertOpen: () => void,
): Promise<PptxQuery> {
  const revision = state.revision,
    selection = JSON.stringify(state.selection);
  const items = await navigator.clipboard.read();
  const objects = items.find((item) => item.types.includes(pptxObjectsMime));
  const rich =
    objects ?? items.find((item) => item.types.includes(pptxTextMime));
  const item = rich ?? items.find((item) => item.types.includes("text/plain"));
  if (!item)
    throw new Error("Clipboard requires presentation text or plain text");
  const blob = await item.getType(
    objects ? pptxObjectsMime : rich ? pptxTextMime : "text/plain",
  );
  if (blob.size > (objects ? 104857600 : rich ? 4194304 : 131068))
    throw new Error("Presentation clipboard exceeds byte budget");
  const text = await blob.text();
  assertOpen();
  const current = await client.execute({ operation: "queryPptx" });
  assertOpen();
  if (
    current.revision !== revision ||
    JSON.stringify(current.selection) !== selection
  )
    throw new Error("Selection changed during clipboard read");
  return client.execute(
    rich
      ? {
          operation: objects ? "pastePptxObjects" : "pastePptxFragment",
          revision,
          fragment: text,
          profile,
        }
      : {
          operation: "replacePptx",
          revision,
          text: text.replace(/\r\n?/g, "\n"),
          profile,
        },
  );
}

export { bindClipboard } from "@open-document/web-core/clipboard";
