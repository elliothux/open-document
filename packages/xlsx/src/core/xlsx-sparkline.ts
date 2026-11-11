import { record } from "@open-document/wasm/abi/validation";
import { xlsxSparklineSourceUnits } from "@open-document/wasm/engine-source";

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
        edit.source.length <= xlsxSparklineSourceUnits)
    ) ||
    !["line", "column", "winLoss"].some((kind) => edit.kind === kind)
  )
    throw new Error("Invalid sparkline command");
}
