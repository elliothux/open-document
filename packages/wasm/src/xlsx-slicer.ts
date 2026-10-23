import type { CellValue } from "./xlsx.js";
import { cellValue } from "./xlsx-grid.js";
import { integer, record } from "./validation.js";

export interface XlsxSlicerMember {
  index: number;
  value: CellValue;
  /** Cached member text; source cell formatting is not inferred. */
  label: string;
  selected: boolean;
  hasData: boolean;
}
export interface XlsxSlicer {
  part: string;
  name: string;
  caption: string;
  cache: string;
  cacheName: string;
  sourceName: string;
  pivotCache: string;
  field: number;
  connections: { sheet: string; part: string; name: string }[];
  columnCount: number;
  startItem: number;
  showCaption: boolean;
  rowHeight: number;
  lockedPosition: boolean;
  style: string;
  sortOrder: "ascending" | "descending";
  crossFilter: "none" | "showItemsWithDataAtTop" | "showItemsWithNoData";
  customListSort: boolean;
  showMissing: boolean;
  members: XlsxSlicerMember[];
}
export interface XlsxSlicers {
  revision: number;
  sheet: string;
  reason: string;
  items: XlsxSlicer[];
}
function text(value: unknown, maximum: number): value is string {
  return (
    typeof value === "string" &&
    value.length <= maximum &&
    value.isWellFormed() &&
    [...value].every((character) => {
      const code = character.charCodeAt(0);
      return code >= 32 || code === 9 || code === 10 || code === 13;
    })
  );
}
function fields(value: Record<string, unknown>, expected: string[]): boolean {
  return (
    Object.keys(value).length === expected.length &&
    expected.every((key) => Object.hasOwn(value, key))
  );
}
export function xlsxSlicers(value: unknown): XlsxSlicers {
  const result = record(value);
  if (
    !fields(result, ["revision", "sheet", "reason", "items"]) ||
    !integer(result.revision, 0, 2147483647) ||
    !text(result.sheet, 1024) ||
    !result.sheet ||
    !text(result.reason, 32767) ||
    !Array.isArray(result.items) ||
    result.items.length > 64 ||
    (result.reason !== "" && result.items.length)
  )
    throw new Error("Invalid slicer catalog");
  const names = new Set<string>();
  let count = 0;
  for (const entry of result.items) {
    const item = record(entry);
    if (
      !fields(item, [
        "part",
        "name",
        "caption",
        "cache",
        "cacheName",
        "sourceName",
        "pivotCache",
        "field",
        "connections",
        "columnCount",
        "startItem",
        "showCaption",
        "rowHeight",
        "lockedPosition",
        "style",
        "sortOrder",
        "crossFilter",
        "customListSort",
        "showMissing",
        "members",
      ])
    )
      throw new Error("Invalid slicer fields");
    for (const key of ["part", "cache", "pivotCache"])
      if (!text(item[key], 1024) || !item[key])
        throw new Error("Invalid slicer part");
    for (const key of ["name", "cacheName", "sourceName"]) {
      const name = item[key];
      if (!text(name, 255) || !name.trim())
        throw new Error("Invalid slicer name");
    }
    if (
      typeof item.name !== "string" ||
      names.has(item.name) ||
      !text(item.caption, 255) ||
      !text(item.style, 255) ||
      !integer(item.field, 0, 79) ||
      !integer(item.columnCount, 1, 64) ||
      !integer(item.startItem, 0, 4095) ||
      typeof item.rowHeight !== "number" ||
      !Number.isFinite(item.rowHeight) ||
      item.rowHeight <= 0 ||
      item.rowHeight > 14400 ||
      typeof item.sortOrder !== "string" ||
      !["ascending", "descending"].includes(item.sortOrder) ||
      typeof item.crossFilter !== "string" ||
      !["none", "showItemsWithDataAtTop", "showItemsWithNoData"].includes(
        item.crossFilter,
      )
    )
      throw new Error("Invalid slicer properties");
    names.add(item.name);
    for (const key of [
      "showCaption",
      "lockedPosition",
      "customListSort",
      "showMissing",
    ])
      if (typeof item[key] !== "boolean")
        throw new Error("Invalid slicer boolean");
    if (
      !Array.isArray(item.connections) ||
      !item.connections.length ||
      item.connections.length > 16
    )
      throw new Error("Invalid slicer connections");
    const parts = new Set<string>();
    for (const entry of item.connections) {
      const connection = record(entry);
      if (
        !fields(connection, ["sheet", "part", "name"]) ||
        !text(connection.sheet, 1024) ||
        !connection.sheet ||
        !text(connection.part, 1024) ||
        !connection.part ||
        parts.has(connection.part) ||
        !text(connection.name, 255) ||
        !connection.name.trim()
      )
        throw new Error("Invalid slicer pivot connection");
      parts.add(connection.part);
    }
    if (
      !Array.isArray(item.members) ||
      !item.members.length ||
      item.members.length > 4096
    )
      throw new Error("Invalid slicer members");
    count += item.members.length;
    const indices = new Set<number>();
    for (const entry of item.members) {
      const member = record(entry),
        cell = record(member.value);
      if (
        !fields(member, ["index", "value", "label", "selected", "hasData"]) ||
        typeof member.index !== "number" ||
        !integer(member.index, 0, 4095) ||
        indices.has(member.index) ||
        !fields(cell, ["kind", "value"]) ||
        !cellValue(cell) ||
        !text(member.label, 32767) ||
        typeof member.selected !== "boolean" ||
        typeof member.hasData !== "boolean"
      )
        throw new Error("Invalid slicer member");
      if (
        (cell.kind === "text" || cell.kind === "error") &&
        !text(cell.value, 32767)
      )
        throw new Error("Invalid slicer member text");
      if (
        cell.kind === "error" &&
        ![
          "#NULL!",
          "#DIV/0!",
          "#VALUE!",
          "#REF!",
          "#NAME?",
          "#NUM!",
          "#N/A",
        ].includes(String(cell.value))
      )
        throw new Error("Invalid slicer member error");
      indices.add(member.index);
    }
  }
  if (count > 16384 || JSON.stringify(value).length > 1048576)
    throw new Error("Slicer catalog exceeds budget");
  return value as XlsxSlicers;
}
