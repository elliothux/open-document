import { integer, record } from "@open-document/wasm/abi/validation";
import {
  xlsxFormulaSourceUnits,
  xlsxTableStyleRegionCount,
  xlsxTableStyleStripeSize,
} from "@open-document/wasm/engine-source";
import {
  checkXlsxCellFormat,
  type XlsxCellFormat,
  type XlsxCellBorder,
} from "./xlsx-format.js";
import {
  checkXlsxFilter,
  type XlsxFilterColumn,
  type XlsxFilterState,
} from "./xlsx-filter.js";

export interface XlsxTableColumn {
  id: number;
  name: string;
  formula: string | null;
  totalFunction: string | null;
  totalLabel: string | null;
  totalFormula: string | null;
}
export interface XlsxTable {
  id: number;
  name: string;
  range: string;
  headerRow: boolean;
  totalRow: boolean;
  columns: XlsxTableColumn[];
  style: string | null;
  firstColumn: boolean;
  lastColumn: boolean;
  rowStripes: boolean;
  columnStripes: boolean;
  readOnlyReason: string;
  filter: XlsxFilterState;
}
export interface XlsxTableStyle {
  name: string | null;
  firstColumn: boolean;
  lastColumn: boolean;
  rowStripes: boolean;
  columnStripes: boolean;
}
export interface XlsxTableStyleChoice {
  name: string;
  readOnlyReason: string;
  elements: XlsxTableStyleElement[];
}
export const xlsxTableStyleRegions = [
  "wholeTable",
  "firstColumnStripe",
  "secondColumnStripe",
  "firstRowStripe",
  "secondRowStripe",
  "lastColumn",
  "firstColumn",
  "headerRow",
  "totalRow",
  "firstHeaderCell",
  "lastHeaderCell",
  "firstTotalCell",
  "lastTotalCell",
] as const;
export interface XlsxTableStyleElement {
  kind: (typeof xlsxTableStyleRegions)[number];
  size: number;
  format: XlsxCellFormat;
  vertical: XlsxCellBorder | null;
  horizontal: XlsxCellBorder | null;
}
function checkTableStyleElements(value: unknown): void {
  if (!Array.isArray(value) || value.length > xlsxTableStyleRegionCount)
    throw new Error("Invalid table style regions");
  const kinds = new Set<string>();
  for (const item of value) {
    const element = record(item);
    if (
      Object.keys(element).length !== 5 ||
      Object.keys(element).some(
        (key) =>
          !["kind", "size", "format", "vertical", "horizontal"].includes(key),
      ) ||
      typeof element.kind !== "string" ||
      !xlsxTableStyleRegions.some((kind) => kind === element.kind) ||
      kinds.has(element.kind) ||
      !integer(element.size, 1, xlsxTableStyleStripeSize)
    )
      throw new Error("Invalid table style region");
    checkXlsxCellFormat(element.format);
    if (element.vertical !== null)
      checkXlsxCellFormat({ left: element.vertical });
    if (element.horizontal !== null)
      checkXlsxCellFormat({ top: element.horizontal });
    kinds.add(element.kind);
  }
}
export type XlsxTableTotalFunction =
  "average" | "countNums" | "count" | "max" | "min" | "stdDev" | "sum" | "var";
export type XlsxTableTotal =
  | { kind: "none" }
  | { kind: "label"; text: string }
  | { kind: "formula"; formula: string }
  | { kind: "aggregate"; function: XlsxTableTotalFunction };
export type XlsxTableEdit =
  | {
      action: "tableStyleDefinition";
      original: string | null;
      name: string;
      elements: XlsxTableStyleElement[];
    }
  | { action: "deleteTableStyle"; name: string; replacement: string | null }
  | { action: "tableStyle"; id: number; style: XlsxTableStyle }
  | { action: "tableFilter"; id: number; columns: XlsxFilterColumn[] }
  | {
      action: "tableFilterClear" | "tableFilterRemove" | "tableFilterReapply";
      id: number;
    }
  | { action: "tableTotals"; id: number; visible: boolean }
  | { action: "tableTotal"; id: number; column: number; total: XlsxTableTotal }
  | {
      action: "tableColumnFormula";
      id: number;
      column: number;
      formula: string | null;
    }
  | { action: "createTable"; range: string; name: string }
  | { action: "resizeTable"; id: number; range: string }
  | { action: "renameTable"; id: number; name: string }
  | { action: "renameTableColumn"; id: number; column: number; name: string };

function tableText(value: unknown, maximum: number): value is string {
  return (
    typeof value === "string" &&
    value.length <= maximum &&
    value.isWellFormed() &&
    !Array.from(value).some((character) => {
      const code = character.codePointAt(0)!;
      return (
        (code < 32 && ![9, 10, 13].includes(code)) ||
        code === 65534 ||
        code === 65535
      );
    })
  );
}
function tableName(value: unknown): value is string {
  return tableText(value, 255) && value.length > 0;
}
function tableStyleName(value: unknown): value is string {
  return (
    tableName(value) &&
    value.trim() === value &&
    !Array.from(value).some(
      (character) =>
        character.codePointAt(0)! < 32 || character.codePointAt(0) === 127,
    )
  );
}
export function checkXlsxTableEdit(value: unknown): void {
  const change = record(value);
  if (
    change.action === "tableStyleDefinition" ||
    change.action === "deleteTableStyle"
  ) {
    const keys =
      change.action === "tableStyleDefinition"
        ? ["action", "original", "name", "elements"]
        : ["action", "name", "replacement"];
    if (
      Object.keys(change).length !== keys.length ||
      Object.keys(change).some((key) => !keys.includes(key)) ||
      !tableStyleName(change.name)
    )
      throw new Error("Invalid table style definition command");
    if (change.action === "tableStyleDefinition") {
      if (!(change.original === null || tableStyleName(change.original)))
        throw new Error("Invalid original table style");
      checkTableStyleElements(change.elements);
    } else if (!(
      change.replacement === null || tableStyleName(change.replacement)
    ))
      throw new Error("Invalid replacement table style");
    return;
  }
  if (change.action === "tableStyle") {
    const style = record(change.style);
    if (
      !integer(change.id, 1, 2147483647) ||
      Object.keys(change).length !== 3 ||
      Object.keys(change).some(
        (key) => !["action", "id", "style"].includes(key),
      ) ||
      Object.keys(style).length !== 5 ||
      Object.keys(style).some(
        (key) =>
          ![
            "name",
            "firstColumn",
            "lastColumn",
            "rowStripes",
            "columnStripes",
          ].includes(key),
      ) ||
      !(style.name === null || tableStyleName(style.name)) ||
      [
        style.firstColumn,
        style.lastColumn,
        style.rowStripes,
        style.columnStripes,
      ].some((value) => typeof value !== "boolean")
    )
      throw new Error("Invalid table style settings");
    return;
  }
  if (
    [
      "tableFilter",
      "tableFilterClear",
      "tableFilterRemove",
      "tableFilterReapply",
    ].includes(String(change.action))
  ) {
    const keys =
      change.action === "tableFilter"
        ? ["action", "id", "columns"]
        : ["action", "id"];
    if (
      !integer(change.id, 1, 2147483647) ||
      Object.keys(change).length !== keys.length ||
      Object.keys(change).some((key) => !keys.includes(key))
    )
      throw new Error("Invalid table filter fields");
    if (change.action === "tableFilter")
      checkXlsxFilter({ range: "A1:A2", columns: change.columns });
    return;
  }
  if (change.action === "tableTotals" || change.action === "tableTotal") {
    const visible = change.action === "tableTotals";
    const keys = visible
      ? ["action", "id", "visible"]
      : ["action", "id", "column", "total"];
    if (
      !integer(change.id, 1, 2147483647) ||
      Object.keys(change).length !== keys.length ||
      Object.keys(change).some((key) => !keys.includes(key))
    )
      throw new Error("Invalid table total fields");
    if (visible) {
      if (typeof change.visible !== "boolean")
        throw new Error("Invalid totals row visibility");
      return;
    }
    if (!integer(change.column, 1, 2147483647))
      throw new Error("Invalid table total column");
    const total = record(change.total);
    const fields =
      total.kind === "none"
        ? ["kind"]
        : total.kind === "label"
          ? ["kind", "text"]
          : total.kind === "formula"
            ? ["kind", "formula"]
            : ["kind", "function"];
    if (
      Object.keys(total).length !== fields.length ||
      Object.keys(total).some((key) => !fields.includes(key)) ||
      !(
        total.kind === "none" ||
        (total.kind === "label" && tableText(total.text, 32767)) ||
        (total.kind === "formula" &&
          tableText(total.formula, xlsxFormulaSourceUnits) &&
          total.formula.trim().length > 0) ||
        (total.kind === "aggregate" &&
          typeof total.function === "string" &&
          [
            "average",
            "countNums",
            "count",
            "max",
            "min",
            "stdDev",
            "sum",
            "var",
          ].includes(total.function))
      )
    )
      throw new Error("Invalid table column total");
    return;
  }
  if (change.action === "tableColumnFormula") {
    if (
      !integer(change.id, 1, 2147483647) ||
      !integer(change.column, 1, 2147483647) ||
      !(
        change.formula === null ||
        (tableText(change.formula, xlsxFormulaSourceUnits) &&
          change.formula.trim().length > 0)
      ) ||
      Object.keys(change).length !== 4 ||
      Object.keys(change).some(
        (key) => !["action", "id", "column", "formula"].includes(key),
      )
    )
      throw new Error("Invalid table column formula");
    return;
  }
  if (change.action === "createTable" || change.action === "resizeTable") {
    const resizing = change.action === "resizeTable";
    const keys = resizing
      ? ["action", "id", "range"]
      : ["action", "range", "name"];
    if (
      !(resizing
        ? integer(change.id, 1, 2147483647)
        : tableName(change.name)) ||
      typeof change.range !== "string" ||
      !/^[A-Z]{1,3}[1-9][0-9]{0,6}:[A-Z]{1,3}[1-9][0-9]{0,6}$/.test(
        change.range,
      ) ||
      Object.keys(change).length !== 3 ||
      Object.keys(change).some((key) => !keys.includes(key))
    )
      throw new Error("Invalid table range edit");
    return;
  }
  const column = change.action === "renameTableColumn";
  if (
    (change.action !== "renameTable" && !column) ||
    !integer(change.id, 1, 2147483647) ||
    !tableName(change.name) ||
    (column && !integer(change.column, 1, 2147483647))
  )
    throw new Error("Invalid table rename");
  const keys = column
    ? ["action", "id", "column", "name"]
    : ["action", "id", "name"];
  if (
    Object.keys(change).length !== keys.length ||
    Object.keys(change).some((key) => !keys.includes(key))
  )
    throw new Error("Invalid table rename fields");
}
