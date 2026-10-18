import { record } from "./validation.js";
import { copiedCellFormat, type XlsxCellFormat } from "./xlsx-format.js";
import type { CellRange, CellValue } from "./xlsx.js";

export interface CopiedCell {
  value: CellValue;
  formula: string | null;
  format: Required<XlsxCellFormat>;
}
export interface CopiedCells {
  top: number;
  left: number;
  date1904: boolean;
  cells: CopiedCell[][];
  merges: CellRange[];
}
export type XlsxPasteMode = "all" | "values" | "formulas" | "format";
export function checkXlsxPasteMode(
  mode: unknown,
): asserts mode is XlsxPasteMode {
  if (
    typeof mode !== "string" ||
    !["all", "values", "formulas", "format"].includes(mode)
  )
    throw new Error("Invalid cell paste mode");
}
export function copiedCells(value: unknown): CopiedCells {
  const fragment = record(value),
    rows = fragment.cells;
  if (
    Object.keys(fragment).length !== 5 ||
    typeof fragment.date1904 !== "boolean" ||
    typeof fragment.top !== "number" ||
    !Number.isInteger(fragment.top) ||
    fragment.top < 1 ||
    typeof fragment.left !== "number" ||
    !Number.isInteger(fragment.left) ||
    fragment.left < 1 ||
    !Array.isArray(rows) ||
    !rows.length ||
    rows.length > 4096 ||
    !Array.isArray(rows[0]) ||
    !rows[0].length ||
    rows.length * rows[0].length > 4096 ||
    fragment.top + rows.length - 1 > 1048576 ||
    fragment.left + rows[0].length - 1 > 16384
  )
    throw new Error("Invalid copied cells rectangle");
  let units = 0;
  const formats: unknown[][] = [];
  for (const row of rows) {
    if (!Array.isArray(row) || row.length !== rows[0].length)
      throw new Error("Copied cells must be rectangular");
    const styles: unknown[] = [];
    for (const source of row) {
      const cell = record(source),
        content = record(cell.value);
      if (
        Object.keys(cell).length !== 3 ||
        Object.keys(content).length !== 2 ||
        !["kind", "value"].every((key) => key in content) ||
        !(
          (content.kind === "blank" && content.value === null) ||
          (content.kind === "number" &&
            typeof content.value === "number" &&
            Number.isFinite(content.value)) ||
          (content.kind === "boolean" && typeof content.value === "boolean") ||
          (content.kind === "text" &&
            typeof content.value === "string" &&
            content.value.length <= 32767) ||
          (content.kind === "error" &&
            typeof content.value === "string" &&
            [
              "#NULL!",
              "#DIV/0!",
              "#VALUE!",
              "#REF!",
              "#NAME?",
              "#NUM!",
              "#N/A",
            ].includes(content.value))
        ) ||
        !(
          cell.formula === null ||
          (typeof cell.formula === "string" &&
            cell.formula.length > 0 &&
            cell.formula.length <= 8192)
        )
      )
        throw new Error("Invalid copied cell value or formula");
      units +=
        String(content.value ?? "").length +
        (typeof cell.formula === "string" ? cell.formula.length : 0);
      if (units > 1048576) throw new Error("Copied cell text exceeds budget");
      styles.push(cell.format);
    }
    formats.push(styles);
  }
  copiedCellFormat({ cells: formats, merges: fragment.merges });
  return value as CopiedCells;
}
