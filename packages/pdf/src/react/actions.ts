import type { PdfEditor } from "../web/index.js";
import type { EditorOutput } from "@open-document/web-core/editor-state";
import type { ClipboardActions } from "@open-document/ui/types";
export async function output(
  editor: PdfEditor,
  kind: string,
): Promise<EditorOutput> {
  if (kind !== "original" && kind !== "print")
    throw new Error("Unsupported PDF output");
  return editor.save();
}
export function clipboard(_editor: PdfEditor): ClipboardActions {
  return { canCopy: true, textMode: true, readOnly: false };
}
