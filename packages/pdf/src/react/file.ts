import { output, clipboard } from "./actions.js";
import { PdfClient, PdfEditor } from "../web/index.js";
import type { EditorOptions } from "./types.js";
import type { OwnedFile } from "./context.js";
import type { OfficeDocument } from "@open-document/ui/types";
import { openWithPassword, readFile } from "@open-document/ui/file";
import {
  documentFailure,
  registerFonts,
} from "@open-document/web-core/connection";
import type { DocumentStage } from "@open-document/wasm/abi/session";
export async function prepareFile(
  options: EditorOptions,
  document: OfficeDocument | File,
  parent: HTMLElement,
  signal: AbortSignal,
): Promise<OwnedFile> {
  signal.throwIfAborted();
  const fromFile = document instanceof File;
  if (!fromFile && document.delimited !== undefined)
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
  let stage: DocumentStage = "worker";
  const abort = () => client?.dispose();
  signal.addEventListener("abort", abort, { once: true });
  const profile = { ...options.resources.profile };
  try {
    const connection = (client = await PdfClient.open(
      options.resources.engine,
      options.resources.workerUrl,
      signal,
    ));
    const budget = options.budget ?? (await connection.defaultBudget());
    const fileBudget =
      options.fileBudget ??
      options.budget ??
      (await connection.defaultFileBudget());
    stage = "input";
    inputLimit = budget.fileBytes;
    if (
      (fromFile ? document.size : (document.bytes?.length ?? 0)) >
      (fromFile ? fileBudget.fileBytes : inputLimit)
    )
      throw new Error("Document input exceeds budget");
    stage = "open";
    if (fromFile && document.size > inputLimit) {
      await connection.openFile(document, fileBudget);
    } else if (!fromFile && document.blank)
      await connection.execute({
        operation: "createPdf",
        width: 595,
        height: 842,
        budget,
      });
    else {
      const bytes = fromFile
        ? await readFile(document, signal)
        : document.bytes;
      if (!bytes) throw new Error("PDF input bytes are required");
      await openWithPassword(
        parent,
        "PDF",
        options.locale === "zh-CN",
        signal,
        (password) =>
          connection.execute({
            operation: "openPdf",
            bytes,
            budget,
            ...(password === undefined ? {} : { password }),
          }),
      );
    }
    stage = "font";
    await registerFonts(connection, options.resources.fonts, signal);
    stage = "layout";
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
      imported: !fromFile && document.blank === true,
      draftCanSave: false,
      cancelDraft: () => opened.editor.cancelDraft(),
      navigate: (index) => {
        const target = opened.editor.snapshot.pages[index];
        if (target) return opened.editor.goToPage(target.id);
      },
      recover: () => opened.editor.refresh(),
      output: (kind) => output(opened.editor, kind),
      clipboard: () => clipboard(opened.editor),
      pageImages: (format) => opened.editor.operations.exportPageImages(format),
      surface,
      inputLimit,
      fileInputLimit: fileBudget.fileBytes,
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
    throw documentFailure(stage, error);
  } finally {
    signal.removeEventListener("abort", abort);
  }
}
