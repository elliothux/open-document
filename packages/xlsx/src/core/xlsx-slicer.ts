import type { CellValue } from "./xlsx.js";
import { integer, record } from "@open-document/wasm/abi/validation";
import { xlsxSlicerMembers } from "@open-document/wasm/engine-source";

const lastSlicerMember = xlsxSlicerMembers - 1;

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
    !integer(value.first, 0, lastSlicerMember) ||
    !integer(value.position, 0, lastSlicerMember) ||
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
            (edit.index === null || integer(edit.index, 0, lastSlicerMember)) &&
            typeof edit.additive === "boolean" &&
            (edit.index !== null || !edit.additive)
          )
        : !integer(edit.position, 0, lastSlicerMember))
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
    edit.indices.length > xlsxSlicerMembers ||
    edit.indices.some((index) => !integer(index, 0, lastSlicerMember)) ||
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
