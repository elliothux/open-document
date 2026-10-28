import type { PdfEditor } from "../web/index.js";
import type { EditorOutput } from "@open-document/web-core/editor-state";
import type { ClipboardActions } from "@open-document/ui/types";
export async function output(
  editor: PdfEditor,
  kind: string,
): Promise<EditorOutput> {
  if (kind === "png" || kind === "jpeg")
    return (await editor.exportPageImages(kind, [editor.snapshot.page]))[0]!;
  if (kind === "html" || kind === "markdown")
    return (await editor.exportText(kind)).output;
  if (kind !== "original" && kind !== "print")
    throw new Error("Unsupported PDF output");
  return editor.save();
}
export function clipboard(_editor: PdfEditor): ClipboardActions {
  return { canCopy: true, textMode: true, readOnly: false };
}
