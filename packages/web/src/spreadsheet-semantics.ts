import type { XlsxViewport, XlsxQuery } from "@open-document/wasm/xlsx";

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
  input: HTMLTextAreaElement,
  active: XlsxQuery["cells"][number] | undefined,
): void {
  input.setAttribute("aria-label", `Cell ${active?.address ?? ""} input`);
  input.setAttribute(
    "aria-description",
    `${active?.display ?? ""}${active?.readOnlyReason ? "; " + active.readOnlyReason : ""}`,
  );
  for (const cell of root.querySelectorAll<HTMLElement>("[role=gridcell]"))
    cell.setAttribute(
      "aria-selected",
      String(cell.dataset.address === active?.address),
    );
}

/** Expose only the bounded, core-provided visible grid to assistive technology. */
export function updateGridSemantics(
  root: HTMLElement,
  cells: XlsxViewport["cells"],
): void {
  const rows = new Map<number, HTMLDivElement>();
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
    row.append(cell);
  }
}
