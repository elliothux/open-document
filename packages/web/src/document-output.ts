import type { FoundationClient } from "./foundation.js";
import type { EditState } from "@open-document/wasm/foundation";
import type { EditorOutput, EditorState } from "./editor-state.js";
import { downloadBytes, docxContentType } from "./download.js";

export async function checkDocxRevision(
  client: FoundationClient,
  revision: number,
  assertOpen: () => void,
): Promise<number> {
  const current = await client.editState();
  assertOpen();
  if (current.revision !== revision)
    throw new Error("Document changed outside this editor");
  return current.revision;
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
      output.format === "docx" ? docxContentType : "application/pdf",
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
