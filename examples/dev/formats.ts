import type { CommonOptions, EditorDocument } from "@open-document/ui/types";
import type { EditorFormat } from "@open-document/web-core/editor-state";
import type { MountedEditor as DocxEditor } from "@open-document/docx/react";
import type { MountedEditor as XlsxEditor } from "@open-document/xlsx/react";
import type { MountedEditor as PptxEditor } from "@open-document/pptx/react";
import type { MountedEditor as PdfEditor } from "@open-document/pdf/react";
export type MountedEditor = DocxEditor | XlsxEditor | PptxEditor | PdfEditor;
export type EditorOptions = CommonOptions & {
  format: EditorFormat;
  document: EditorDocument;
};
export async function mountEditor(
  container: HTMLElement,
  options: EditorOptions,
): Promise<MountedEditor> {
  switch (options.format) {
    case "docx":
      return (await import("@open-document/docx/react")).mountEditor(
        container,
        options,
      );
    case "xlsx":
      return (await import("@open-document/xlsx/react")).mountEditor(
        container,
        options,
      );
    case "pptx":
      return (await import("@open-document/pptx/react")).mountEditor(
        container,
        options,
      );
    case "pdf":
      return (await import("@open-document/pdf/react")).mountEditor(
        container,
        options,
      );
  }
}
