import type { PresentationEditor } from "../web/index.js";
import type { EditorOutput } from "@open-document/web-core/editor-state";
import type { ClipboardActions } from "@open-document/ui/types";
export async function output(
  editor: PresentationEditor,
  kind: string,
): Promise<EditorOutput> {
  switch (kind) {
    case "original":
      return editor.save();
    case "print":
    case "pdf":
      return editor.exportPdf(true);
    case "pdf-current":
      return editor.exportPdf(false);
    case "png":
      return editor.exportPng();
    case "jpeg":
      return editor.exportJpeg();
    default:
      throw new Error("Unsupported presentation output");
  }
}
export function clipboard(editor: PresentationEditor): ClipboardActions {
  const query = editor.query;
  const textMode = query.selection.mode === "text";
  const objects = query.objects.filter((object) =>
    query.selection.objects.includes(object.id),
  );
  return {
    canCopy:
      textMode ||
      (objects.length > 0 &&
        objects.every(
          (object) =>
            !object.parent &&
            ["shape", "image", "group", "table", "chart"].includes(
              object.kind,
            ) &&
            !object.duplicateReason &&
            object.equations.length === 0 &&
            (!object.media || (!object.media.reason && !!object.media.poster)),
        )),
    textMode,
    readOnly:
      textMode &&
      !!query.objects.find((object) => object.id === query.selection.object)
        ?.textReadOnlyReason,
    cut: () => editor.copy(true),
    paste: (text) => editor.paste(text),
    pasteClipboard: () => editor.pasteClipboard(),
  };
}
