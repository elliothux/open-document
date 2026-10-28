import { output, clipboard } from "./actions.js";
import { PptxClient, PresentationEditor } from "../web/index.js";
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
  surface.dataset.format = "pptx";
  Object.assign(surface.style, {
    position: "absolute",
    inset: "0",
    visibility: "hidden",
    pointerEvents: "none",
  });
  parent.append(surface);
  let client: PptxClient | undefined;
  let file: { format: "pptx"; editor: PresentationEditor } | undefined;
  let inputLimit = 0;
  const abort = () => client?.dispose();
  signal.addEventListener("abort", abort, { once: true });
  const profile = { ...options.resources.profile };
  const fonts = async (connection: PptxClient) => {
    for (const font of options.resources.fonts) {
      signal.throwIfAborted();
      await connection.addFont(font.bytes, font.identity);
    }
  };
  try {
    const connection = (client = await PptxClient.open(
      options.resources.engine,
      options.resources.workerUrl,
      signal,
    ));
    const budget = options.budget ?? (await connection.defaultBudget());
    inputLimit = Math.min(budget.fileBytes, budget.retainedBytes);
    if ((document.bytes?.length ?? 0) > inputLimit)
      throw new Error("Document input exceeds budget");
    if (document.blank)
      await connection.execute({ operation: "createPptx", budget });
    else
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

    signal.throwIfAborted();
    let cleanup: Promise<void> | undefined;
    const opened = file;
    return {
      ...opened,
      originalName: document.name,
      imported: false,
      draftCanSave: false,
      navigate: (index) => {
        const target = opened.editor.query.slides[index];
        if (target) return opened.editor.showSlide(target.id);
      },
      recover: () => opened.editor.refresh(),
      output: (kind) => output(opened.editor, kind),
      clipboard: () => clipboard(opened.editor),
      pageImages: (format) =>
        opened.editor.exportPageImages(1, 67108864, false, format),
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
