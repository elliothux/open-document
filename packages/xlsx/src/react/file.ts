import { output, clipboard } from "./actions.js";
import { XlsxClient, SpreadsheetEditor } from "../web/index.js";
import type { EditorOptions } from "./types.js";
import type { OwnedFile } from "./context.js";
import type { OfficeDocument } from "@open-document/ui/types";
import {
  documentFailure,
  registerFonts,
} from "@open-document/web-core/connection";
import type { DocumentStage } from "@open-document/wasm/abi/session";
export async function prepareFile(
  options: EditorOptions,
  document: OfficeDocument,
  parent: HTMLElement,
  signal: AbortSignal,
): Promise<OwnedFile> {
  signal.throwIfAborted();
  if (document.delimited !== undefined && !/\.(csv|tsv)$/i.test(document.name))
    throw new Error("Import options require CSV/TSV input in an XLSX editor");
  const surface = parent.ownerDocument.createElement("div");
  surface.className = "od-surface";
  surface.dataset.format = "xlsx";
  Object.assign(surface.style, {
    position: "absolute",
    inset: "0",
    visibility: "hidden",
    pointerEvents: "none",
  });
  parent.append(surface);
  let client: XlsxClient | undefined;
  let file: { format: "xlsx"; editor: SpreadsheetEditor } | undefined;
  let inputLimit = 0;
  let stage: DocumentStage = "worker";
  const abort = () => client?.dispose();
  signal.addEventListener("abort", abort, { once: true });
  const profile = { ...options.resources.profile };
  try {
    const connection = (client = await XlsxClient.open(
      options.resources.engine,
      options.resources.workerUrl,
      signal,
    ));
    const budget = options.budget ?? (await connection.defaultBudget());
    stage = "input";
    inputLimit = Math.min(budget.fileBytes, budget.retainedBytes);
    if ((document.bytes?.length ?? 0) > inputLimit)
      throw new Error("Document input exceeds budget");
    stage = "open";
    if (document.blank)
      await connection.execute({ operation: "createXlsx", budget });
    else if (/\.(csv|tsv)$/i.test(document.name))
      await connection.execute({
        operation: "importXlsxDelimited",
        bytes: document.bytes,
        delimiter: /\.tsv$/i.test(document.name) ? "\t" : ",",
        budget,
        options: document.delimited,
      });
    else
      await connection.execute({
        operation: "openXlsx",
        bytes: document.bytes,
        budget,
      });
    stage = "font";
    await registerFonts(connection, options.resources.fonts, signal);
    stage = "layout";
    file = {
      format: "xlsx",
      editor: await SpreadsheetEditor.mount(surface, connection, profile),
    };

    signal.throwIfAborted();
    let cleanup: Promise<void> | undefined;
    const opened = file;
    return {
      ...opened,
      originalName: document.name.replace(/\.(csv|tsv)$/i, ".xlsx"),
      imported: /\.(csv|tsv)$/i.test(document.name),
      draftCanSave: true,
      cancelDraft: () => opened.editor.cancelDraft(),
      navigate: (index) => {
        return opened.editor.showPrintPage(index);
      },
      recover: () => opened.editor.refresh(),
      output: (kind) => output(opened.editor, kind),
      clipboard: () => clipboard(opened.editor),
      surface,
      inputLimit,
      delimitedInputLimit: Math.min(
        inputLimit,
        opened.editor.inputLimits.delimitedBytes,
      ),
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
