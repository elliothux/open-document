import type { XlsxViewport, XlsxQuery } from "@open-document/wasm/xlsx";
import type { SpreadsheetPrint } from "./spreadsheet-print.js";

export interface SpreadsheetEditorData {
  readonly query: XlsxQuery;
  readonly printPage: number;
  readonly printPages: number;
  readonly printVisible: boolean;
}

export function spreadsheetSnapshotData(
  query: XlsxQuery,
  print: SpreadsheetPrint,
  old: SpreadsheetEditorData,
): SpreadsheetEditorData {
  return old.query === query &&
    old.printPage === print.page &&
    old.printPages === print.pageCount &&
    old.printVisible === print.visible
    ? old
    : {
        query,
        printPage: print.page,
        printPages: print.pageCount,
        printVisible: print.visible,
      };
}

export function activeGridCell(
  state: XlsxQuery,
  layout: XlsxViewport | undefined,
) {
  const range = state.selection.range;
  return (
    state.cells.find(
      (cell) => cell.row === range.top && cell.column === range.left,
    ) ??
    layout?.cells.find(
      (item) => item.cell.row === range.top && item.cell.column === range.left,
    )?.cell
  );
}

export function updateGridSelection(
  root: HTMLElement,
  active: XlsxQuery["cells"][number] | undefined,
): void {
  for (const cell of root.querySelectorAll<HTMLElement>("[role=gridcell]"))
    cell.setAttribute(
      "aria-selected",
      String(cell.dataset.address === active?.address),
    );
}

/** Expose only the bounded, core-provided visible grid to assistive technology. */
export function updateGridSemantics(
  root: HTMLElement,
  { cells, notes }: XlsxViewport,
  { sparklines }: XlsxQuery,
): void {
  const rows = new Map<number, HTMLDivElement>();
  const descriptions = new Map(
    notes.map((note) => [note.address, `${note.author}: ${note.text}`]),
  );
  root.replaceChildren();
  for (const item of cells) {
    let row = rows.get(item.cell.row);
    if (!row) {
      row = document.createElement("div");
      row.setAttribute("role", "row");
      row.setAttribute("aria-rowindex", String(item.cell.row));
      rows.set(item.cell.row, row);
      root.append(row);
    }
    const cell = document.createElement("div");
    cell.dataset.address = item.cell.address;
    cell.setAttribute("role", "gridcell");
    cell.setAttribute("aria-colindex", String(item.cell.column));
    cell.setAttribute("aria-readonly", String(!!item.cell.readOnlyReason));
    cell.setAttribute(
      "aria-label",
      `${item.cell.address}: ${item.display}${item.cell.readOnlyReason ? "; " + item.cell.readOnlyReason : ""}`,
    );
    cell.textContent = item.display;
    const sparkline = sparklines.items.find(
      (line) => line.cell === item.cell.address,
    );
    const description = [
      descriptions.get(item.cell.address),
      sparkline && `Sparkline ${sparkline.kind}: ${sparkline.source}`,
    ]
      .filter(Boolean)
      .join("; ");
    if (description) cell.setAttribute("aria-description", description);
    row.append(cell);
  }
}
