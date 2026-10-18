import { integer, record } from "./validation.js";

export interface XlsxTableColumn {
  id: number;
  name: string;
  calculated: boolean;
}
export interface XlsxTable {
  id: number;
  name: string;
  range: string;
  headerRow: boolean;
  totalRow: boolean;
  columns: XlsxTableColumn[];
  style: string | null;
  readOnlyReason: string;
}
export type XlsxTableEdit =
  | { action: "renameTable"; id: number; name: string }
  | { action: "renameTableColumn"; id: number; column: number; name: string };

function tableName(value: unknown): value is string {
  return (
    typeof value === "string" &&
    value.length > 0 &&
    value.length <= 255 &&
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
export function checkXlsxTableEdit(value: unknown): void {
  const change = record(value);
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
  let columns = 0;
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
        typeof column.calculated !== "boolean" ||
        columnIds.has(column.id) ||
        columnNames.has(column.name.toUpperCase())
      )
        throw new Error("Invalid table column");
      columnIds.add(column.id);
      columnNames.add(column.name.toUpperCase());
    }
    ids.add(table.id);
    names.add(table.name.toUpperCase());
  }
  return value as XlsxTable[];
}
