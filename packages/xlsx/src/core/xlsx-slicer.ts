import type { CellValue } from "./xlsx.js";
import { cellValue } from "./xlsx-grid.js";
import { integer, record } from "@open-document/wasm/abi/validation";

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
export interface XlsxSlicerSettings {
  pivot: string;
  field: number;
  name: string;
  caption: string;
  width: number;
  height: number;
}
export interface XlsxSlicerGesture {
  first: number;
  position: number;
  x: number;
  y: number;
  additive: boolean;
  commit: boolean;
}
export function checkXlsxSlicerGesture(input: unknown): void {
  const value = record(input);
  if (
    !fields(value, ["first", "position", "x", "y", "additive", "commit"]) ||
    !integer(value.first, 0, 4095) ||
    !integer(value.position, 0, 4095) ||
    ![value.x, value.y].every(
      (number) =>
        typeof number === "number" &&
        Number.isFinite(number) &&
        Math.abs(number) <= 14400,
    ) ||
    typeof value.additive !== "boolean" ||
    typeof value.commit !== "boolean"
  )
    throw new Error("Invalid slicer gesture");
}
export function checkXlsxSlicerSettings(value: unknown): void {
  const settings = record(value);
  if (
    !fields(settings, [
      "pivot",
      "field",
      "name",
      "caption",
      "width",
      "height",
    ]) ||
    !text(settings.pivot, 1024) ||
    !settings.pivot.trim() ||
    !integer(settings.field, 0, 63) ||
    !text(settings.name, 255) ||
    !settings.name.trim() ||
    !text(settings.caption, 255) ||
    !settings.caption.trim() ||
    ![settings.width, settings.height].every(
      (value) =>
        typeof value === "number" &&
        Number.isFinite(value) &&
        value >= 0.1 &&
        value <= 14400,
    )
  )
    throw new Error("Invalid native slicer settings");
}
export type XlsxSlicerEdit =
  | { action: "deleteSlicer"; name: string }
  | {
      action: "filterSlicer";
      name: string;
      indices: number[];
    }
  | {
      action: "selectSlicer";
      layout: number;
      id: string;
      index: number | null;
      additive: boolean;
    }
  | { action: "scrollSlicer"; layout: number; id: string; position: number };
export function checkXlsxSlicerEdit(value: unknown): void {
  const edit = record(value);
  if (edit.action === "deleteSlicer") {
    if (
      !fields(edit, ["action", "name"]) ||
      !text(edit.name, 255) ||
      !edit.name.trim()
    )
      throw new Error("Invalid slicer deletion command");
    return;
  }
  if (edit.action === "selectSlicer" || edit.action === "scrollSlicer") {
    const selecting = edit.action === "selectSlicer";
    if (
      !fields(
        edit,
        selecting
          ? ["action", "layout", "id", "index", "additive"]
          : ["action", "layout", "id", "position"],
      ) ||
      !integer(edit.layout, 1, 2147483647) ||
      typeof edit.id !== "string" ||
      !/^[1-9][0-9]{0,9}$/.test(edit.id) ||
      (selecting
        ? !(
            (edit.index === null || integer(edit.index, 0, 4095)) &&
            typeof edit.additive === "boolean" &&
            (edit.index !== null || !edit.additive)
          )
        : !integer(edit.position, 0, 4095))
    )
      throw new Error("Invalid slicer pointer command");
    return;
  }
  if (
    !fields(edit, ["action", "name", "indices"]) ||
    edit.action !== "filterSlicer" ||
    !text(edit.name, 255) ||
    !edit.name.trim() ||
    !Array.isArray(edit.indices) ||
    !edit.indices.length ||
    edit.indices.length > 4096 ||
    edit.indices.some((index) => !integer(index, 0, 4095)) ||
    new Set(edit.indices).size !== edit.indices.length
  )
    throw new Error("Invalid slicer command");
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
