import { integer, record } from "./validation.js";
import {
  checkXlsxFilter,
  xlsxFilterState,
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
export type XlsxTableTotalFunction =
  "average" | "countNums" | "count" | "max" | "min" | "stdDev" | "sum" | "var";
export type XlsxTableTotal =
  | { kind: "none" }
  | { kind: "label"; text: string }
  | { kind: "formula"; formula: string }
  | { kind: "aggregate"; function: XlsxTableTotalFunction };
export type XlsxTableEdit =
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
export function checkXlsxTableEdit(value: unknown): void {
  const change = record(value);
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
      !(
        style.name === null ||
        (typeof style.name === "string" &&
          /^TableStyle(?:Medium(?:[1-9]|1[0-9]|2[0-8])|Light(?:[1-9]|1[0-9]|2[01])|Dark(?:[1-9]|1[01]))$/.exec(
            style.name,
          )?.[0] === style.name)
      ) ||
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
          tableText(total.formula, 8192) &&
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
        (tableText(change.formula, 8192) && change.formula.trim().length > 0)
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

export function xlsxTables(value: unknown): XlsxTable[] {
  if (!Array.isArray(value) || value.length > 256)
    throw new Error("Invalid table catalog");
  const ids = new Set<number>(),
    names = new Set<string>();
  let columns = 0,
    formulaUnits = 0,
    filterUnits = 0;
  for (const entry of value) {
    const table = record(entry);
    if (
      typeof table.id !== "number" ||
      !integer(table.id, 1, 2147483647) ||
      !tableName(table.name) ||
      ids.has(table.id) ||
      names.has(table.name.toUpperCase()) ||
      typeof table.range !== "string" ||
      !/^[A-Z]{1,3}[1-9][0-9]{0,6}(:[A-Z]{1,3}[1-9][0-9]{0,6})?$/.test(
        table.range,
      ) ||
      typeof table.headerRow !== "boolean" ||
      typeof table.totalRow !== "boolean" ||
      (table.style !== null && !tableName(table.style)) ||
      [
        table.firstColumn,
        table.lastColumn,
        table.rowStripes,
        table.columnStripes,
      ].some((value) => typeof value !== "boolean") ||
      typeof table.readOnlyReason !== "string" ||
      !Array.isArray(table.columns) ||
      !table.columns.length
    )
      throw new Error("Invalid table definition");
    const addresses = table.range.split(":").map((address) => {
      const match = /^([A-Z]+)([0-9]+)$/.exec(address);
      if (!match) throw new Error("Invalid table range");
      let column = 0;
      for (const letter of match[1]!)
        column = column * 26 + letter.charCodeAt(0) - 64;
      return { column, row: Number(match[2]) };
    });
    const first = addresses[0]!,
      last = addresses[1] ?? first;
    if (
      !integer(first.column, 1, 16384) ||
      !integer(last.column, first.column, 16384) ||
      !integer(first.row, 1, 1048576) ||
      !integer(last.row, first.row, 1048576) ||
      last.column - first.column + 1 !== table.columns.length ||
      last.row - first.row + 1 <
        Number(table.headerRow) + Number(table.totalRow)
    )
      throw new Error("Invalid table range or column count");
    const filter = xlsxFilterState(table.filter);
    for (const column of filter.catalog) {
      filterUnits += column.title.length;
      for (const entry of column.values) filterUnits += entry.value.length;
      if (filterUnits > 2097152)
        throw new Error("Native table filter catalogs exceed text budget");
    }
    const start = table.range.split(":")[0]!,
      end = table.range.split(":")[1] ?? start;
    const expectedFilter = `${start}:${end.replace(/[0-9]+$/, String(last.row - Number(table.totalRow)))}`;
    if (filter.range && (!table.headerRow || filter.range !== expectedFilter))
      throw new Error("Invalid native table filter range");
    columns += table.columns.length;
    if (columns > 4096) throw new Error("Table columns exceed budget");
    const columnIds = new Set<number>(),
      columnNames = new Set<string>();
    for (const item of table.columns) {
      const column = record(item);
      if (
        typeof column.id !== "number" ||
        !integer(column.id, 1, 2147483647) ||
        !tableName(column.name) ||
        !(column.formula === null || tableText(column.formula, 8192)) ||
        !(
          column.totalFunction === null || tableText(column.totalFunction, 255)
        ) ||
        !(column.totalLabel === null || tableText(column.totalLabel, 32767)) ||
        !(
          column.totalFormula === null || tableText(column.totalFormula, 8192)
        ) ||
        columnIds.has(column.id) ||
        columnNames.has(column.name.toUpperCase())
      )
        throw new Error("Invalid table column");
      for (const text of [
        column.formula,
        column.totalFunction,
        column.totalLabel,
        column.totalFormula,
      ])
        if (typeof text === "string") formulaUnits += text.length;
      if (formulaUnits > 1048576)
        throw new Error("Table formula and total metadata exceeds budget");
      columnIds.add(column.id);
      columnNames.add(column.name.toUpperCase());
    }
    ids.add(table.id);
    names.add(table.name.toUpperCase());
  }
  return value as XlsxTable[];
}
