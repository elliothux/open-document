import type { XlsxViewport } from "@open-document/wasm/xlsx";

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
