import { record } from "@open-document/wasm/abi/validation";

export type XlsxSparklineKind = "line" | "column" | "winLoss";
export interface XlsxSparkline {
  cell: string;
  source: string;
  kind: XlsxSparklineKind;
}
export interface XlsxSparklines {
  items: XlsxSparkline[];
  readOnlyReason: string;
}
export type XlsxSparklineEdit = {
  action: "sparkline";
  cell: string;
  source: string | null;
  kind: XlsxSparklineKind;
};

export function checkXlsxSparklineEdit(value: unknown): void {
  const edit = record(value);
  if (
    Object.keys(edit).length !== 4 ||
    Object.keys(edit).some(
      (k) => !["action", "cell", "source", "kind"].includes(k),
    ) ||
    edit.action !== "sparkline" ||
    typeof edit.cell !== "string" ||
    !/^[A-Z]{1,3}[1-9][0-9]{0,6}$/.test(edit.cell) ||
    !(
      edit.source === null ||
      (typeof edit.source === "string" &&
        edit.source.length > 0 &&
        edit.source.length <= 256)
    ) ||
    !["line", "column", "winLoss"].some((kind) => edit.kind === kind)
  )
    throw new Error("Invalid sparkline command");
}

export function xlsxSparklines(value: unknown): XlsxSparklines {
  const state = record(value);
  if (
    !Array.isArray(state.items) ||
    state.items.length > 256 ||
    typeof state.readOnlyReason !== "string"
  )
    throw new Error("Invalid sparkline state");
  const cells = new Set<string>();
  for (const value of state.items) {
    const item = record(value);
    checkXlsxSparklineEdit({
      action: "sparkline",
      cell: item.cell,
      source: item.source,
      kind: item.kind,
    });
    if (
      typeof item.cell !== "string" ||
      typeof item.source !== "string" ||
      cells.has(item.cell)
    )
      throw new Error("Invalid sparkline source or duplicate cell");
    cells.add(item.cell);
  }
  return value as XlsxSparklines;
}
