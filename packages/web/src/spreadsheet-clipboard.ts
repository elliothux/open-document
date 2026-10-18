import {
  copiedCells,
  type XlsxQuery,
  type XlsxPasteMode,
} from "@open-document/wasm/xlsx";
import type { XlsxClient } from "./xlsx.js";
import type { SpreadsheetEditor } from "./spreadsheet-editor.js";
import { checkCopiedFormatFonts } from "./spreadsheet-format.js";
import { bindClipboard } from "./clipboard-input.js";

const cellMime = "web application/x-open-document-cells";

export function bindSpreadsheetClipboard(
  input: HTMLElement,
  signal: AbortSignal,
  host: Pick<SpreadsheetEditor, "copy" | "paste">,
  composing: () => boolean,
  native: () => boolean,
  handle: (action: () => Promise<unknown>) => void,
  reject: (error: Error) => void,
): void {
  bindClipboard(
    input,
    signal,
    (cut) => {
      if (cut) reject(new Error("Cut is unsupported; copy or clear cells"));
      else handle(() => host.copy());
    },
    (text) => handle(() => host.paste(text)),
    reject,
    composing,
    native,
  );
}

export async function copyCellData(
  client: XlsxClient,
  revision: number,
  structured = true,
): Promise<void> {
  if (!structured) {
    await navigator.clipboard.writeText(await client.copy(revision));
    return;
  }
  const cells = await client.captureCells(revision);
  const text = await client.copy(revision);
  const json = JSON.stringify(cells);
  if (json.length > 4194304)
    throw new Error("Cell clipboard exceeds byte budget");
  await navigator.clipboard.write([
    new ClipboardItem({
      "text/plain": new Blob([text], { type: "text/plain" }),
      [cellMime]: new Blob([json], {
        type: "application/x-open-document-cells",
      }),
    }),
  ]);
}

export async function pasteSpreadsheetCells(
  client: XlsxClient,
  state: XlsxQuery,
  profile: Record<string, string>,
  mode: XlsxPasteMode,
  transpose: boolean,
  acceptWarnings: boolean,
  closed: () => boolean,
): Promise<XlsxQuery> {
  const items = await navigator.clipboard.read();
  const item = items.find((item) => item.types.includes(cellMime));
  if (!item) throw new Error("Copy cells before using cell paste options");
  const blob = await item.getType(cellMime);
  if (blob.size > 8388608)
    throw new Error("Cell clipboard exceeds byte budget");
  const cells = copiedCells(JSON.parse(await blob.text()));
  if (closed()) throw new Error("Editor is disposed");
  if (mode === "all" || mode === "format")
    checkCopiedFormatFonts(
      {
        cells: cells.cells.map((row) => row.map((cell) => cell.format)),
        merges: cells.merges,
      },
      state.formatting,
      profile,
    );
  return client.pasteCells(
    state.revision,
    cells,
    mode,
    transpose,
    acceptWarnings,
  );
}
