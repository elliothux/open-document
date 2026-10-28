import { output, clipboard } from "./actions.js";
import { PdfClient, PdfEditor } from "../web/index.js";
import type { EditorOptions } from "./types.js";
import type { OwnedFile } from "./context.js";
import type { OfficeDocument } from "@open-document/ui/types";
export async function prepareFile(
  options: EditorOptions,
  document: OfficeDocument,
  parent: HTMLElement,
  signal: AbortSignal,
): Promise<OwnedFile> {
  signal.throwIfAborted();
  if (document.delimited !== undefined && true)
    throw new Error("Import options require CSV/TSV input in an XLSX editor");
  const surface = parent.ownerDocument.createElement("div");
  surface.className = "od-surface";
  surface.dataset.format = "pdf";
  Object.assign(surface.style, {
    position: "absolute",
    inset: "0",
    visibility: "hidden",
    pointerEvents: "none",
  });
  parent.append(surface);
  let client: PdfClient | undefined;
  let file: { format: "pdf"; editor: PdfEditor } | undefined;
  let inputLimit = 0;
  const abort = () => client?.dispose();
  signal.addEventListener("abort", abort, { once: true });
  const profile = { ...options.resources.profile };
  const fonts = async (connection: PdfClient) => {
    for (const font of options.resources.fonts) {
      signal.throwIfAborted();
      await connection.addFont(font.bytes, font.identity);
    }
  };
  try {
    const connection = (client = await PdfClient.open(
      options.resources.engine,
      options.resources.workerUrl,
      signal,
    ));
    const budget = options.budget ?? (await connection.defaultBudget());
    inputLimit = budget.fileBytes;
    if (document.bytes && document.bytes.length > inputLimit)
      throw new Error("Document input exceeds budget");
    if (document.blank)
      await connection.execute({
        operation: "createPdf",
        width: 595,
        height: 842,
        budget,
      });
    else {
      if (!document.bytes) throw new Error("PDF input bytes are required");
      await connection.execute({
        operation: "openPdf",
        bytes: document.bytes,
        budget,
      });
    }
    await fonts(connection);
    file = {
      format: "pdf",
      editor: await PdfEditor.create(surface, connection, profile, signal),
    };

    signal.throwIfAborted();
    let cleanup: Promise<void> | undefined;
    const opened = file;
    return {
      ...opened,
      originalName: document.name,
      imported: document.blank === true,
      draftCanSave: false,
      cancelDraft: () => opened.editor.cancelDraft(),
      navigate: (index) => {
        const target = opened.editor.snapshot.pages[index];
        if (target) return opened.editor.goToPage(target.id);
      },
      recover: () => opened.editor.refresh(),
      output: (kind) => output(opened.editor, kind),
      clipboard: () => clipboard(opened.editor),
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
    signal.throwIfAborted();
    throw error;
  } finally {
    signal.removeEventListener("abort", abort);
  }
}
