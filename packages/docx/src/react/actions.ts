import type { DocumentEditor } from "../web/index.js";
import { pasteDocxSelection } from "../web/index.js";
import type { EditorOutput } from "@open-document/web-core/editor-state";
import type { ClipboardActions } from "@open-document/ui/types";
export async function output(
  editor: DocumentEditor,
  kind: string,
): Promise<EditorOutput> {
  switch (kind) {
    case "original":
      return editor.saveDocx();
    case "print":
    case "pdf":
    case "pdf-current":
      return editor.exportPdf();
    case "png":
      return editor.exportPng();
    case "html":
      return editor.exportHtml();
    case "markdown":
      return editor.exportMarkdown();
    default:
      throw new Error("Unsupported document output");
  }
}
export function clipboard(editor: DocumentEditor): ClipboardActions {
  return {
    canCopy: true,
    textMode: true,
    readOnly: false,
    richText: true,
    cut: () => editor.copy(true),
    paste: (text, format, mode) =>
      format === "html"
        ? editor.pasteHtml(text, mode)
        : format === "markdown"
          ? editor.pasteMarkdown(text, mode)
          : editor.paste(text),
    pasteClipboard: () => pasteDocxSelection(editor),
  };
}
