import type { CellValue } from "./xlsx.js";
import { cellValue } from "./xlsx-grid.js";
import { xlsxBounds } from "./xlsx-geometry.js";
import { integer, record } from "./validation.js";

export const xlsxPivotAggregates = [
  "sum",
  "count",
  "countNums",
  "average",
  "min",
  "max",
  "product",
  "stdDev",
  "stdDevp",
  "var",
  "varp",
] as const;
export interface XlsxPivotValue {
  /** Zero-based source column. */
  field: number;
  aggregate: (typeof xlsxPivotAggregates)[number];
  name: string;
}
export interface XlsxPivotSettings {
  sourceSheet: string;
  source: string;
  /** Ordered zero-based source columns. */
  rows: number[];
  /** Ordered zero-based source columns on the column axis. */
  columns: number[];
  filters: XlsxPivotFilter[];
  values: XlsxPivotValue[];
}
export interface XlsxPivotFilter {
  field: number;
  /** Null includes future source members; a nonempty array keeps an explicit selection. */
  values: CellValue[] | null;
}
export type XlsxPivotEdit =
  | {
      action: "createPivot";
      name: string;
      destination: string;
      settings: XlsxPivotSettings;
      sourceRevision: number;
    }
  | {
      action: "updatePivot";
      part: string;
      settings: XlsxPivotSettings;
      sourceRevision: number;
    }
  | { action: "refreshPivot" | "deletePivot"; part: string };
export interface XlsxPivotPreview {
  revision: number;
  settings: XlsxPivotSettings;
  fields: string[];
  recordCount: number;
  filteredCount: number;
  filterItems: { value: CellValue; label: string }[][];
  groups: number;
  truncated: boolean;
  columnMembers: { members: CellValue[]; formats: string[] }[];
  columnTotals: CellValue[][];
  rows: {
    members: CellValue[];
    formats: string[];
    values: CellValue[];
    total: CellValue[];
  }[];
  total: CellValue[];
}
export interface XlsxPivots {
  revision: number;
  items: {
    part: string;
    name: string;
    range: string;
    sourceSheet: string | null;
    source: string | null;
    stale: boolean;
    settings: XlsxPivotSettings | null;
    reason: string;
  }[];
}
function text(value: unknown, max: number): value is string {
  return (
    typeof value === "string" &&
    value.length > 0 &&
    value.length <= max &&
    value.isWellFormed() &&
    Array.from(value).every(
      (char) => char.charCodeAt(0) >= 32 || ["\t", "\n", "\r"].includes(char),
    )
  );
}
function fields(value: Record<string, unknown>, names: string[]): boolean {
  return (
    Object.keys(value).length === names.length &&
    Object.keys(value).every((key) => names.includes(key))
  );
}
function filterValue(value: unknown): string {
  if (!cellValue(value)) throw new Error("Invalid pivot filter value");
  const item = record(value);
  if (
    !fields(item, ["kind", "value"]) ||
    (item.kind === "text" && !text(item.value, 32767)) ||
    (item.kind === "error" &&
      ![
        "#NULL!",
        "#DIV/0!",
        "#VALUE!",
        "#REF!",
        "#NAME?",
        "#NUM!",
        "#N/A",
      ].includes(String(item.value)))
  )
    throw new Error("Invalid pivot filter value");
  return JSON.stringify({
    kind: item.kind,
    value: item.kind === "text" ? String(item.value).toLowerCase() : item.value,
  });
}
export function checkXlsxPivotSettings(value: unknown): void {
  const settings = record(value),
    bounds = xlsxBounds(settings.source, 65600),
    width = bounds.right - bounds.left + 1;
  if (
    !fields(settings, [
      "sourceSheet",
      "source",
      "rows",
      "columns",
      "filters",
      "values",
    ]) ||
    !text(settings.sourceSheet, 1024) ||
    bounds.bottom <= bounds.top ||
    width > 64 ||
    (bounds.bottom - bounds.top) * width > 65536 ||
    !Array.isArray(settings.rows) ||
    !settings.rows.length ||
    settings.rows.length > 8 ||
    new Set(settings.rows).size !== settings.rows.length ||
    settings.rows.some((field) => !integer(field, 0, width - 1)) ||
    !Array.isArray(settings.columns) ||
    settings.columns.length > 8 ||
    settings.columns.some((field) => !integer(field, 0, width - 1)) ||
    new Set([...settings.rows, ...settings.columns]).size !==
      settings.rows.length + settings.columns.length ||
    !Array.isArray(settings.filters) ||
    settings.filters.length > 8 ||
    !Array.isArray(settings.values) ||
    !settings.values.length ||
    settings.values.length > 8
  )
    throw new Error("Invalid pivot settings");
  const names = new Set<string>();
  const axes = new Set([...settings.rows, ...settings.columns]);
  let units = 0;
  for (const value of settings.filters) {
    const filter = record(value);
    if (
      !fields(filter, ["field", "values"]) ||
      !integer(filter.field, 0, width - 1) ||
      axes.has(filter.field) ||
      !(
        filter.values === null ||
        (Array.isArray(filter.values) &&
          filter.values.length > 0 &&
          filter.values.length <= 4096)
      )
    )
      throw new Error("Invalid pivot report filter");
    axes.add(filter.field);
    if (Array.isArray(filter.values)) {
      const seen = new Set<string>();
      for (const value of filter.values) {
        const key = filterValue(value);
        units += key.length;
        if (seen.has(key) || units > 1048576)
          throw new Error("Duplicate or excessive pivot report values");
        seen.add(key);
      }
    }
  }
  for (const item of settings.values) {
    const value = record(item);
    if (
      !fields(value, ["field", "aggregate", "name"]) ||
      !integer(value.field, 0, width - 1) ||
      !xlsxPivotAggregates.some((kind) => kind === value.aggregate) ||
      !text(value.name, 255) ||
      !value.name.trim() ||
      names.has(value.name.toLowerCase())
    )
      throw new Error("Invalid pivot value field");
    names.add(value.name.toLowerCase());
  }
}
export function checkXlsxPivotEdit(value: unknown): void {
  const edit = record(value);
  if (edit.action === "refreshPivot" || edit.action === "deletePivot") {
    if (!fields(edit, ["action", "part"]) || !text(edit.part, 1024))
      throw new Error("Invalid pivot refresh");
    return;
  }
  if (edit.action === "updatePivot") {
    if (
      !fields(edit, ["action", "part", "settings", "sourceRevision"]) ||
      !text(edit.part, 1024) ||
      !integer(edit.sourceRevision, 0, 2147483647)
    )
      throw new Error("Invalid pivot field update");
    checkXlsxPivotSettings(edit.settings);
    return;
  }
  if (
    edit.action !== "createPivot" ||
    !fields(edit, [
      "action",
      "name",
      "destination",
      "settings",
      "sourceRevision",
    ]) ||
    !text(edit.name, 255) ||
    !edit.name.trim() ||
    !integer(edit.sourceRevision, 0, 2147483647)
  )
    throw new Error("Invalid pivot creation");
  const destination = xlsxBounds(edit.destination);
  if (
    destination.top !== destination.bottom ||
    destination.left !== destination.right
  )
    throw new Error("Pivot destination must be one cell");
  checkXlsxPivotSettings(edit.settings);
}
export function xlsxPivotPreview(value: unknown): XlsxPivotPreview {
  const result = record(value);
  checkXlsxPivotSettings(result.settings);
  const settings = record(result.settings),
    rows = settings.rows as number[],
    columns = settings.columns as number[],
    filters = settings.filters as XlsxPivotFilter[],
    values = settings.values as XlsxPivotValue[],
    bounds = xlsxBounds(settings.source, 65600);
  if (
    !integer(result.revision, 0, 2147483647) ||
    !Array.isArray(result.fields) ||
    result.fields.length !== bounds.right - bounds.left + 1 ||
    result.fields.some((field) => !text(field, 255)) ||
    new Set(result.fields).size !== result.fields.length ||
    !integer(result.recordCount, 1, bounds.bottom - bounds.top) ||
    !integer(result.filteredCount, 0, Number(result.recordCount)) ||
    !integer(
      result.groups,
      Number(result.filteredCount) > 0 ? 1 : 0,
      Math.min(4096, Number(result.filteredCount)),
    ) ||
    result.truncated !== Number(result.groups) > 20 ||
    !Array.isArray(result.rows) ||
    result.rows.length !== Math.min(20, Number(result.groups)) ||
    !Array.isArray(result.total) ||
    result.total.length !== values.length ||
    !result.total.every(cellValue) ||
    !Array.isArray(result.columnMembers) ||
    result.columnMembers.length > 4096 ||
    result.columnMembers.length > Number(result.filteredCount) ||
    (columns.length === 0
      ? result.columnMembers.length !== 0
      : (result.columnMembers.length === 0) !== (result.filteredCount === 0)) ||
    !Array.isArray(result.columnTotals) ||
    result.columnTotals.length !==
      (columns.length ? result.columnMembers.length : 1) ||
    !Array.isArray(result.filterItems) ||
    result.filterItems.length !== filters.length ||
    result.columnTotals.some(
      (total) =>
        !Array.isArray(total) ||
        total.length !== values.length ||
        !total.every(cellValue),
    )
  )
    throw new Error("Invalid pivot preview");
  for (const items of result.filterItems) {
    if (!Array.isArray(items) || !items.length || items.length > 4096)
      throw new Error("Invalid pivot report items");
    const seen = new Set<string>();
    for (const value of items) {
      const item = record(value),
        key = filterValue(item.value);
      if (seen.has(key) || !(item.label === "" || text(item.label, 32767)))
        throw new Error("Invalid pivot report item");
      seen.add(key);
    }
  }
  for (const item of result.rows) {
    const row = record(item);
    if (
      !Array.isArray(row.members) ||
      row.members.length !== rows.length ||
      !row.members.every(cellValue) ||
      !Array.isArray(row.formats) ||
      row.formats.length !== rows.length ||
      row.formats.some((format) => !text(format, 4096)) ||
      !Array.isArray(row.values) ||
      row.values.length !==
        values.length * Math.max(1, result.columnMembers.length) ||
      !row.values.every(cellValue) ||
      !Array.isArray(row.total) ||
      row.total.length !== values.length ||
      !row.total.every(cellValue)
    )
      throw new Error("Invalid pivot preview row");
  }
  for (const item of result.columnMembers) {
    const column = record(item);
    if (
      !Array.isArray(column.members) ||
      column.members.length !== columns.length ||
      !column.members.every(cellValue) ||
      !Array.isArray(column.formats) ||
      column.formats.length !== columns.length ||
      column.formats.some((format) => !text(format, 4096))
    )
      throw new Error("Invalid pivot column preview");
  }
  if (JSON.stringify(value).length > 1048576)
    throw new Error("Pivot preview exceeds text budget");
  return value as XlsxPivotPreview;
}
export function xlsxPivots(value: unknown): XlsxPivots {
  const result = record(value);
  if (
    !integer(result.revision, 0, 2147483647) ||
    !Array.isArray(result.items) ||
    result.items.length > 64
  )
    throw new Error("Invalid pivot catalog");
  const parts = new Set<string>();
  for (const item of result.items) {
    const pivot = record(item);
    xlsxBounds(pivot.range, 17179869184);
    if (!text(pivot.part, 1024) || parts.has(pivot.part))
      throw new Error("Invalid or duplicate pivot part");
    if (!text(pivot.name, 255)) throw new Error("Invalid pivot name");
    if (!(pivot.sourceSheet === null || text(pivot.sourceSheet, 1024)))
      throw new Error("Invalid pivot source sheet");
    if (!(pivot.source === null || text(pivot.source, 64)))
      throw new Error("Invalid pivot source range");
    if (typeof pivot.stale !== "boolean")
      throw new Error("Invalid pivot cache state");
    if (typeof pivot.reason !== "string")
      throw new Error("Invalid pivot protection reason");
    if (pivot.settings === null ? !pivot.reason : !!pivot.reason)
      throw new Error("Pivot settings and protection reason disagree");
    if (pivot.source !== null) xlsxBounds(pivot.source, 17179869184);
    if (pivot.settings !== null) {
      checkXlsxPivotSettings(pivot.settings);
      const settings = record(pivot.settings);
      if (
        settings.sourceSheet !== pivot.sourceSheet ||
        settings.source !== pivot.source
      )
        throw new Error("Pivot source disagrees with settings");
    }
    parts.add(pivot.part);
  }
  return value as XlsxPivots;
}
