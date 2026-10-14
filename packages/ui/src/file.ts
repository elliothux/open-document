import { FoundationClient } from "@open-document/web/foundation";
import { XlsxClient } from "@open-document/web/xlsx";
import { PptxClient } from "@open-document/web/pptx";
import { PdfClient } from "@open-document/web/pdf";
import { DocumentEditor } from "@open-document/web/editor";
import { SpreadsheetEditor } from "@open-document/web/spreadsheet-editor";
import { PresentationEditor } from "@open-document/web/presentation-editor";
import { PdfEditor } from "@open-document/web/pdf-editor";
import type {
  EditorDocument,
  EditorFile,
  EditorOptions,
  OwnedFile,
} from "./types.js";

/** A current file or one candidate owns its Worker; low-level editors borrow it. */
export async function prepareFile(
  options: EditorOptions,
  document: EditorDocument,
  parent: HTMLElement,
  signal: AbortSignal,
): Promise<OwnedFile> {
  signal.throwIfAborted();
  const surface = parent.ownerDocument.createElement("div");
  surface.className = "od-surface";
  Object.assign(surface.style, {
    position: "absolute",
    inset: "0",
    visibility: "hidden",
    pointerEvents: "none",
  });
  parent.append(surface);
  let client:
    FoundationClient | XlsxClient | PptxClient | PdfClient | undefined;
  let file: EditorFile | undefined;
  let inputLimit = 0;
  const abort = () => client?.dispose();
  signal.addEventListener("abort", abort, { once: true });
  const profile = { ...options.resources.profile };
  const fonts = async (connection: NonNullable<typeof client>) => {
    for (const font of options.resources.fonts) {
      signal.throwIfAborted();
      await connection.addFont(font.bytes, font.identity);
    }
  };
  try {
    switch (options.format) {
      case "docx": {
        const connection = (client = await FoundationClient.open(
          options.resources.wasm,
          options.resources.workerUrl,
          signal,
        ));
        const budget = options.budget ?? (await connection.defaultBudget());
        inputLimit = Math.min(budget.fileBytes, budget.retainedBytes);
        if (document.bytes.length > inputLimit)
          throw new Error("Document input exceeds budget");
        await connection.openDocx(document.bytes, budget);
        await fonts(connection);
        file = {
          format: "docx",
          editor: await DocumentEditor.create(
            surface,
            connection,
            profile,
            signal,
          ),
        };
        break;
      }
      case "xlsx": {
        const connection = (client = await XlsxClient.open(
          options.resources.wasm,
          options.resources.workerUrl,
          signal,
        ));
        const budget = options.budget ?? (await connection.defaultBudget());
        inputLimit = Math.min(budget.fileBytes, budget.retainedBytes);
        if (document.bytes.length > inputLimit)
          throw new Error("Document input exceeds budget");
        await connection.openXlsx(document.bytes, budget);
        await fonts(connection);
        file = {
          format: "xlsx",
          editor: await SpreadsheetEditor.mount(surface, connection, profile),
        };
        break;
      }
      case "pptx": {
        const connection = (client = await PptxClient.open(
          options.resources.wasm,
          options.resources.workerUrl,
          signal,
        ));
        const budget = options.budget ?? (await connection.defaultBudget());
        inputLimit = Math.min(budget.fileBytes, budget.retainedBytes);
        if (document.bytes.length > inputLimit)
          throw new Error("Document input exceeds budget");
        await connection.execute({
          operation: "openPptx",
          bytes: document.bytes,
          budget,
        });
        await fonts(connection);
        file = {
          format: "pptx",
          editor: await PresentationEditor.create(
            surface,
            connection,
            profile,
            signal,
          ),
        };
        break;
      }
      case "pdf": {
        const connection = (client = await PdfClient.open(
          options.resources.wasm,
          options.resources.workerUrl,
          signal,
        ));
        const budget = options.budget ?? (await connection.defaultBudget());
        inputLimit = budget.fileBytes;
        if (document.bytes.length > inputLimit)
          throw new Error("Document input exceeds budget");
        await connection.execute({
          operation: "openPdf",
          bytes: document.bytes,
          budget,
        });
        await fonts(connection);
        file = {
          format: "pdf",
          editor: await PdfEditor.create(surface, connection, profile, signal),
        };
        break;
      }
    }
    signal.throwIfAborted();
    let cleanup: Promise<void> | undefined;
    const opened = file;
    const connection = client;
    return {
      ...opened,
      surface,
      inputLimit,
      dispose() {
        cleanup ??= (async () => {
          try {
            await opened.editor.dispose();
          } finally {
            connection.dispose();
            surface.remove();
          }
        })();
        return cleanup;
      },
    };
  } catch (error) {
    try {
      await file?.editor.dispose();
    } finally {
      client?.dispose();
      surface.remove();
    }
    throw error;
  } finally {
    signal.removeEventListener("abort", abort);
  }
}
