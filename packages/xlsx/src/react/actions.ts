import type { SpreadsheetEditor } from "../web/index.js";
import type { EditorOutput } from "@open-document/web-core/editor-state";
import type { ClipboardActions } from "@open-document/ui/types";
export async function output(
  editor: SpreadsheetEditor,
  kind: string,
): Promise<EditorOutput> {
  switch (kind) {
    case "original":
      return editor.save();
    case "print":
    case "pdf":
      return editor.exportPdf({ sheets: "visible" });
    case "pdf-current":
      return editor.exportPdf(null);
    case "csv":
      return editor.exportCsv(false);
    case "csv-selection":
      return editor.exportCsv(true);
    default:
      throw new Error("Unsupported workbook output");
  }
}
export function clipboard(editor: SpreadsheetEditor): ClipboardActions {
  return {
    canCopy: true,
    textMode: true,
    readOnly: false,
    paste: (text) => editor.paste(text),
  };
}
