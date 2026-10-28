import {
  copiedCells,
  type XlsxQuery,
  type XlsxPasteMode,
  checkXlsxSheetEdit,
} from "../core/xlsx.js";
import type { XlsxClient } from "./xlsx.js";
import type { SpreadsheetEditor } from "./spreadsheet-editor.js";
import { checkCopiedFormatFonts } from "./spreadsheet-format.js";
import { bindClipboard } from "@open-document/web-core/clipboard";

const cellMime = "web application/x-open-document-cells";
const cutMime = "web application/x-open-document-cut";
const drawingCutMime = "web application/x-open-document-drawing-cut";
const drawingMime = "web application/x-open-document-drawing";
const books = new WeakMap<XlsxClient, string>();
let pendingCut = false;
let pendingDrawing = false;

export function resetCellClipboard(client: XlsxClient): void {
  books.delete(client);
}

export function bindSpreadsheetClipboard(
  input: HTMLElement,
  signal: AbortSignal,
  host: Pick<
    SpreadsheetEditor,
    "copy" | "cutSelection" | "paste" | "pasteCells" | "pasteDrawing"
  >,
  composing: () => boolean,
  native: () => boolean,
  handle: (action: () => Promise<unknown>) => void,
  reject: (error: Error) => void,
): void {
  bindClipboard(
    input,
    signal,
    (cut) => {
      if (cut) handle(() => host.cutSelection());
      else handle(() => host.copy());
    },
    (text) =>
      handle(async () => {
        const items =
          pendingCut || pendingDrawing ? await navigator.clipboard.read() : [];
        if (
          items.some(
            (item) =>
              item.types.includes(drawingCutMime) ||
              item.types.includes(drawingMime),
          )
        )
          await host.pasteDrawing();
        else if (items.some((item) => item.types.includes(cutMime)))
          await host.pasteCells();
        else await host.paste(text);
      }),
    reject,
    composing,
    native,
  );
}

export async function copyCellData(
  client: XlsxClient,
  state: XlsxQuery,
  structured = true,
  cut = false,
): Promise<void> {
  if (typeof cut !== "boolean") throw new Error("Invalid cell cut option");
  if (!structured) {
    await navigator.clipboard.writeText(await client.copy(state.revision));
    pendingCut = false;
    pendingDrawing = false;
    return;
  }
  const text = await client.copy(state.revision);
  const data: Record<string, Blob> = {
    "text/plain": new Blob([text], { type: "text/plain" }),
  };
  if (cut) {
    let book = books.get(client);
    if (!book) books.set(client, (book = crypto.randomUUID()));
    data[cutMime] = new Blob(
      [
        JSON.stringify({
          book,
          revision: state.revision,
          sheet: state.sheet,
          range: state.selection.address,
        }),
      ],
      { type: "application/x-open-document-cut" },
    );
  } else {
    const json = JSON.stringify(await client.captureCells(state.revision));
    if (json.length > 4194304)
      throw new Error("Cell clipboard exceeds byte budget");
    data[cellMime] = new Blob([json], {
      type: "application/x-open-document-cells",
    });
  }
  await navigator.clipboard.write([new ClipboardItem(data)]);
  pendingCut = cut;
  pendingDrawing = false;
}

export async function cutSpreadsheetDrawing(
  client: XlsxClient,
  state: XlsxQuery,
  objectId: string,
): Promise<void> {
  checkXlsxSheetEdit({
    action: "moveDrawing",
    sourceSheet: state.sheet,
    objectId,
  });
  let book = books.get(client);
  if (!book) books.set(client, (book = crypto.randomUUID()));
  await navigator.clipboard.write([
    new ClipboardItem({
      "text/plain": new Blob([""], { type: "text/plain" }),
      [drawingCutMime]: new Blob(
        [
          JSON.stringify({
            book,
            revision: state.revision,
            sheet: state.sheet,
            objectId,
          }),
        ],
        { type: drawingCutMime.slice(4) },
      ),
    }),
  ]);
  pendingDrawing = true;
  pendingCut = false;
}

export async function copySpreadsheetDrawing(
  client: XlsxClient,
  state: XlsxQuery,
  objectId: string,
  profile: Record<string, string>,
): Promise<void> {
  const copied = await client.captureDrawing(
    state.revision,
    state.sheet,
    objectId,
    profile,
  );
  await navigator.clipboard.write([
    new ClipboardItem({
      "text/plain": new Blob([copied.text], { type: "text/plain" }),
      [drawingMime]: new Blob([copied.fragment], {
        type: drawingMime.slice(4),
      }),
    }),
  ]);
  pendingDrawing = true;
  pendingCut = false;
}

export async function pasteSpreadsheetDrawing(
  client: XlsxClient,
  state: XlsxQuery,
  profile: Record<string, string>,
  closed: () => boolean,
  prepare: (fragment: string) => Promise<void>,
): Promise<XlsxQuery> {
  const item = (await navigator.clipboard.read()).find(
    (item) =>
      item.types.includes(drawingCutMime) || item.types.includes(drawingMime),
  );
  if (!item) throw new Error("Copy or cut a worksheet drawing before pasting");
  if (!item.types.includes(drawingCutMime)) {
    const blob = await item.getType(drawingMime);
    if (blob.size > 8388608)
      throw new Error("Drawing clipboard exceeds byte budget");
    const fragment = await blob.text();
    if (closed()) throw new Error("Editor is disposed");
    await prepare(fragment);
    if (closed()) throw new Error("Editor is disposed");
    return client.pasteDrawing(state.revision, state.sheet, fragment, profile);
  }
  const blob = await item.getType(drawingCutMime);
  if (blob.size > 4096) throw new Error("Invalid drawing cut clipboard");
  const value: unknown = JSON.parse(await blob.text());
  if (!value || typeof value !== "object" || Array.isArray(value))
    throw new Error("Invalid drawing cut clipboard");
  const cut = value as Record<string, unknown>;
  if (
    Object.keys(cut).length !== 4 ||
    typeof cut.book !== "string" ||
    cut.book !== books.get(client) ||
    cut.revision !== state.revision ||
    typeof cut.sheet !== "string" ||
    typeof cut.objectId !== "string"
  )
    throw new Error(
      "Drawing cut clipboard has expired or belongs to another workbook",
    );
  const change = {
    action: "moveDrawing",
    sourceSheet: cut.sheet,
    objectId: cut.objectId,
  } as const;
  checkXlsxSheetEdit(change);
  if (closed()) throw new Error("Editor is disposed");
  return client.editSheet(state.revision, state.sheet, change);
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
  const item = items.find(
    (item) => item.types.includes(cutMime) || item.types.includes(cellMime),
  );
  if (!item) throw new Error("Copy cells before using cell paste options");
  if (item.types.includes(cutMime)) {
    const marker = await item.getType(cutMime);
    if (marker.size > 4096) throw new Error("Invalid cut clipboard");
    const value: unknown = JSON.parse(await marker.text());
    if (!value || typeof value !== "object" || Array.isArray(value))
      throw new Error("Invalid cut clipboard");
    const cut = value as Record<string, unknown>;
    if (
      Object.keys(cut).length !== 4 ||
      typeof cut.book !== "string" ||
      cut.book !== books.get(client) ||
      cut.revision !== state.revision ||
      typeof cut.sheet !== "string" ||
      !cut.sheet ||
      cut.sheet.length > 1024 ||
      typeof cut.range !== "string" ||
      !cut.range ||
      cut.range.length > 64
    )
      throw new Error(
        "Cut clipboard has expired or belongs to another workbook",
      );
    if (mode !== "all" || transpose)
      throw new Error("Cut cells require Paste all cells without transpose");
    if (closed()) throw new Error("Editor is disposed");
    return client.editSheet(state.revision, state.sheet, {
      action: "moveCells",
      sourceSheet: cut.sheet,
      source: cut.range,
      destination: state.selection.address,
    });
  }
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
