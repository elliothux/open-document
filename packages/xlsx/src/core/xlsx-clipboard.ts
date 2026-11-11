import { record, integer } from "@open-document/wasm/abi/validation";
import {
  xlsxCellFragmentCells,
  xlsxCellFragmentTextUnits,
  xlsxCellTextUnits,
  xlsxCopiedHyperlinkCount,
  xlsxCopiedHyperlinkLabelUnits,
  xlsxCopiedHyperlinkTextUnits,
  xlsxCopiedNoteSourceUnits,
  xlsxCopiedRuleRanges,
  xlsxCopiedRuleTextUnits,
  xlsxFormulaSourceUnits,
  xlsxSparklineCount,
  xlsxSparklineSourceCells,
  xlsxWorksheetColumns,
  xlsxWorksheetRows,
} from "@open-document/wasm/engine-source";
import {
  checkXlsxConditionalFormat,
  type XlsxConditionalFormat,
} from "./xlsx-conditional.js";
import {
  checkXlsxDataValidation,
  type XlsxDataValidation,
} from "./xlsx-validation.js";
import { copiedCellFormat, type XlsxCellFormat } from "./xlsx-format.js";
import type { CellRange, CellValue } from "./xlsx.js";
import { checkXlsxHyperlinkTarget } from "./xlsx-sheet.js";
import type { XlsxSparklineKind } from "./xlsx-sparkline.js";

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
  conditional: CopiedConditional[];
  validations: CopiedValidation[];
  hyperlinks: CopiedHyperlink[];
  notes: CopiedNotes | null;
  sparklines: CopiedSparkline[];
}
export interface CopiedSparkline {
  cell: { row: number; column: number };
  source: CellRange | null;
  kind: XlsxSparklineKind;
}
export interface CopiedNotes {
  comments: string;
  vml: string | null;
  threads: string | null;
  people: string | null;
}
export interface CopiedHyperlink {
  range: CellRange;
  target: string;
  display: string | null;
  tooltip: string | null;
}
export interface CopiedConditional {
  ranges: CellRange[];
  anchor: { row: number; column: number };
  settings: XlsxConditionalFormat;
}
export interface CopiedValidation {
  ranges: CellRange[];
  anchor: { row: number; column: number };
  settings: XlsxDataValidation;
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
    Object.keys(fragment).length !== 10 ||
    typeof fragment.date1904 !== "boolean" ||
    typeof fragment.top !== "number" ||
    !Number.isInteger(fragment.top) ||
    fragment.top < 1 ||
    typeof fragment.left !== "number" ||
    !Number.isInteger(fragment.left) ||
    fragment.left < 1 ||
    !Array.isArray(rows) ||
    !rows.length ||
    rows.length > xlsxCellFragmentCells ||
    !Array.isArray(rows[0]) ||
    !rows[0].length ||
    rows.length * rows[0].length > xlsxCellFragmentCells ||
    fragment.top + rows.length - 1 > xlsxWorksheetRows ||
    fragment.left + rows[0].length - 1 > xlsxWorksheetColumns
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
            content.value.length <= xlsxCellTextUnits) ||
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
            cell.formula.length <= xlsxFormulaSourceUnits)
        )
      )
        throw new Error("Invalid copied cell value or formula");
      units +=
        String(content.value ?? "").length +
        (typeof cell.formula === "string" ? cell.formula.length : 0);
      if (units > xlsxCellFragmentTextUnits)
        throw new Error("Copied cell text exceeds budget");
      styles.push(cell.format);
    }
    formats.push(styles);
  }
  const format = copiedCellFormat({ cells: formats, merges: fragment.merges });
  let count = 0,
    ruleUnits = 0;
  for (const key of ["conditional", "validations"] as const) {
    const rules: unknown = fragment[key];
    if (!Array.isArray(rules) || rules.length > xlsxCopiedRuleRanges)
      throw new Error("Invalid copied cell rules");
    for (const value of rules) {
      const rule = record(value),
        anchor = record(rule.anchor),
        ranges: unknown = rule.ranges;
      if (
        Object.keys(rule).length !== 3 ||
        Object.keys(anchor).length !== 2 ||
        !integer(anchor.row, 1, xlsxWorksheetRows) ||
        !integer(anchor.column, 1, xlsxWorksheetColumns) ||
        !Array.isArray(ranges) ||
        ranges.length === 0 ||
        ranges.length > xlsxCopiedRuleRanges
      )
        throw new Error("Invalid copied rule geometry");
      for (const value of ranges) {
        const range = record(value);
        if (
          Object.keys(range).length !== 4 ||
          !integer(range.top, fragment.top, fragment.top + rows.length - 1) ||
          !integer(
            range.bottom,
            Number(range.top),
            fragment.top + rows.length - 1,
          ) ||
          !integer(
            range.left,
            fragment.left,
            fragment.left + rows[0].length - 1,
          ) ||
          !integer(
            range.right,
            Number(range.left),
            fragment.left + rows[0].length - 1,
          )
        )
          throw new Error("Copied rule leaves source rectangle");
      }
      if (key === "conditional") checkXlsxConditionalFormat(rule.settings);
      else checkXlsxDataValidation(rule.settings);
      count += ranges.length;
      ruleUnits += JSON.stringify(rule.settings).length;
      if (count > xlsxCopiedRuleRanges || ruleUnits > xlsxCopiedRuleTextUnits)
        throw new Error("Copied cell rules exceed budget");
    }
  }
  const hyperlinks: unknown = fragment.hyperlinks;
  if (
    !Array.isArray(hyperlinks) ||
    hyperlinks.length > xlsxCopiedHyperlinkCount
  )
    throw new Error("Invalid copied hyperlinks");
  const occupied = new Set<number>();
  let linkUnits = 0;
  for (const source of hyperlinks) {
    const link = record(source),
      range = record(link.range);
    if (
      Object.keys(link).length !== 4 ||
      Object.keys(range).length !== 4 ||
      !integer(range.top, fragment.top, fragment.top + rows.length - 1) ||
      !integer(
        range.bottom,
        Number(range.top),
        fragment.top + rows.length - 1,
      ) ||
      !integer(range.left, fragment.left, fragment.left + rows[0].length - 1) ||
      !integer(
        range.right,
        Number(range.left),
        fragment.left + rows[0].length - 1,
      ) ||
      typeof link.target !== "string"
    )
      throw new Error("Invalid copied hyperlink geometry");
    checkXlsxHyperlinkTarget(link.target);
    linkUnits += link.target.length;
    for (const key of ["display", "tooltip"] as const) {
      const text = link[key];
      if (
        text !== null &&
        (typeof text !== "string" ||
          text.length > xlsxCopiedHyperlinkLabelUnits)
      )
        throw new Error("Invalid copied hyperlink metadata");
      if (typeof text === "string") linkUnits += text.length;
    }
    if (linkUnits > xlsxCopiedHyperlinkTextUnits)
      throw new Error("Copied hyperlink text exceeds budget");
    for (let row = Number(range.top); row <= Number(range.bottom); row++)
      for (
        let column = Number(range.left);
        column <= Number(range.right);
        column++
      ) {
        const key =
          (row - fragment.top) * rows[0].length + column - fragment.left;
        if (occupied.has(key)) throw new Error("Overlapping copied hyperlinks");
        occupied.add(key);
      }
  }
  if (fragment.notes !== null) {
    const notes = record(fragment.notes);
    if (
      Object.keys(notes).length !== 4 ||
      typeof notes.comments !== "string" ||
      !notes.comments ||
      !notes.comments.isWellFormed() ||
      !(
        notes.vml === null ||
        (typeof notes.vml === "string" &&
          !!notes.vml &&
          notes.vml.isWellFormed())
      ) ||
      !(
        (notes.threads === null && notes.people === null) ||
        (typeof notes.threads === "string" &&
          !!notes.threads &&
          notes.threads.isWellFormed() &&
          typeof notes.people === "string" &&
          !!notes.people &&
          notes.people.isWellFormed())
      ) ||
      notes.comments.length +
        (typeof notes.vml === "string" ? notes.vml.length : 0) +
        (typeof notes.threads === "string" ? notes.threads.length : 0) +
        (typeof notes.people === "string" ? notes.people.length : 0) >
        xlsxCopiedNoteSourceUnits
    )
      throw new Error("Invalid copied cell notes");
  }
  const sparklines: unknown = fragment.sparklines;
  if (!Array.isArray(sparklines) || sparklines.length > xlsxSparklineCount)
    throw new Error("Invalid copied sparklines");
  const destinations = new Set<number>();
  for (const value of sparklines) {
    const item = record(value),
      cell = record(item.cell),
      row = Number(cell.row) - fragment.top + 1,
      column = Number(cell.column) - fragment.left + 1;
    if (
      Object.keys(item).length !== 3 ||
      Object.keys(cell).length !== 2 ||
      !integer(cell.row, fragment.top, fragment.top + rows.length - 1) ||
      !integer(
        cell.column,
        fragment.left,
        fragment.left + rows[0].length - 1,
      ) ||
      typeof item.kind !== "string" ||
      !["line", "column", "winLoss"].includes(item.kind) ||
      format.merges.some(
        (range) =>
          row >= range.top &&
          row <= range.bottom &&
          column >= range.left &&
          column <= range.right,
      )
    )
      throw new Error("Invalid copied sparkline destination or type");
    const key =
      (Number(cell.row) - fragment.top) * rows[0].length +
      Number(cell.column) -
      fragment.left;
    if (destinations.has(key)) throw new Error("Overlapping copied sparklines");
    destinations.add(key);
    if (item.source !== null) {
      const source = record(item.source);
      if (
        Object.keys(source).length !== 4 ||
        !integer(source.top, 1, xlsxWorksheetRows) ||
        !integer(source.bottom, Number(source.top), xlsxWorksheetRows) ||
        !integer(source.left, 1, xlsxWorksheetColumns) ||
        !integer(source.right, Number(source.left), xlsxWorksheetColumns) ||
        !(source.top === source.bottom || source.left === source.right) ||
        Number(source.bottom) -
          Number(source.top) +
          Number(source.right) -
          Number(source.left) >=
          xlsxSparklineSourceCells
      )
        throw new Error("Invalid copied sparkline source");
    }
  }
  return value as CopiedCells;
}
