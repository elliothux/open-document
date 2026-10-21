import type { FoundationClient } from "./foundation.js";
import { DocumentError, type EditState } from "@open-document/wasm/foundation";
import type { EditorOutput, EditorState } from "./editor-state.js";
import { downloadBytes, docxContentType } from "./download.js";
import type { CanvasSurface } from "./canvas-surface.js";
import type { PageLayout } from "@open-document/wasm/preview";

export async function checkDocxRevision(
  client: FoundationClient,
  revision: number,
  assertOpen: () => void,
): Promise<number> {
  const current = await client.editState();
  assertOpen();
  if (current.revision !== revision)
    throw new Error("Document changed outside this editor");
  if (current.compositionId !== null || current.drawingGestureId !== null)
    throw new DocumentError(
      "busy",
      "Complete or cancel pending edits before output",
      "",
      -1,
    );
  return current.revision;
}

export async function docxOutputs(
  client: FoundationClient,
  expectedRevision: number,
  layout: PageLayout,
  surface: CanvasSurface,
  page: number,
  format: "docx" | "pdf" | "png" | "images" | "html" | "markdown",
  outputBytes: number,
  scale: number,
  observable: EditorState<EditState>,
  assertOpen: () => void,
): Promise<readonly EditorOutput[]> {
  const revision = await checkDocxRevision(
    client,
    expectedRevision,
    assertOpen,
  );
  const buffers: Uint8Array[] = [];
  if (format === "png" || format === "images") {
    if (layout.revision !== revision)
      throw new Error("Page layout is stale; refresh before exporting");
    if (layout.diagnostics.length)
      throw new Error(
        `PNG requires supported layout: ${layout.diagnostics.join("; ")}`,
      );
    let remaining = outputBytes;
    const pages = format === "images" ? layout.regions.keys() : [page];
    for (const index of pages) {
      assertOpen();
      if (remaining === 0) throw new Error("PNG pages exceed byte budget");
      const bytes = await surface.exportImage(layout, index, scale, remaining);
      assertOpen();
      remaining -= bytes.byteLength;
      buffers.push(bytes);
    }
  } else {
    buffers.push(
      format === "docx"
        ? await client.saveDocx()
        : format === "html" || format === "markdown"
          ? await client.exportMarkup(revision, format, outputBytes)
          : await client.exportPdf(outputBytes, layout.id),
    );
  }
  assertOpen();
  return Object.freeze(
    buffers.map((bytes) =>
      observable.output(revision, format === "images" ? "png" : format, bytes),
    ),
  );
}

export function downloadDocxOutput(
  output: EditorOutput,
  filename: string,
  observable: EditorState<EditState>,
  reportFailure: boolean,
): void {
  try {
    downloadBytes(
      output.bytes,
      output.format === "docx"
        ? docxContentType
        : output.format === "html"
          ? "text/html;charset=utf-8"
          : output.format === "markdown"
            ? "text/markdown;charset=utf-8"
            : "application/pdf",
      filename,
    );
  } catch (error) {
    if (reportFailure)
      observable.update({
        error: "Download failed. The document can be saved again.",
      });
    throw error;
  }
  observable.markDownloaded(output);
}
