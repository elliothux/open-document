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
export const xlsxPivotValueModes = [
  "normal",
  "percentOfTotal",
  "percentOfRow",
  "percentOfCol",
  "index",
  "percentOfParentRow",
  "percentOfParentCol",
  "runTotal",
  "percentOfRunningTotal",
  "rankAscending",
  "rankDescending",
  "difference",
  "percent",
  "percentDiff",
  "percentOfParent",
] as const;
export const xlsxPivotCompareModes: readonly string[] = [
  "difference",
  "percent",
  "percentDiff",
];
export const xlsxPivotBaseModes: readonly string[] = [
  "runTotal",
  "percentOfRunningTotal",
  "rankAscending",
  "rankDescending",
  "difference",
  "percent",
  "percentDiff",
  "percentOfParent",
];
export type XlsxPivotBaseItem = "previous" | "next" | CellValue;
export interface XlsxPivotValue {
  /** Zero-based source column. */
  field: number;
  aggregate: (typeof xlsxPivotAggregates)[number];
  showDataAs: (typeof xlsxPivotValueModes)[number];
  /** Source axis column for cumulative/rank modes; null for other modes. */
  baseField: number | null;
  /** Required only for comparison modes. Typed members survive cache index changes. */
  baseItem: XlsxPivotBaseItem | null;
  name: string;
}
export interface XlsxPivotSettings {
  sourceSheet: string;
  /** Header/data rectangle, or a structured table name on sourceSheet. */
  source: string;
  /** Ordered zero-based source columns. */
  rows: number[];
  /** Ordered zero-based source columns on the column axis. */
  columns: number[];
  filters: XlsxPivotFilter[];
  /** Outer row/column fields whose automatic subtotals follow each group. */
  subtotals: number[];
  numberGroups: XlsxPivotNumberGroup[];
  dateGroups: XlsxPivotDateGroup[];
  values: XlsxPivotValue[];
}
export const xlsxPivotDateUnits = [
  "years",
  "quarters",
  "months",
  "days",
] as const;
export interface XlsxPivotDateGroup {
  field: number;
  /** Unique calendar levels in coarse-to-fine order; bounds follow source dates. */
  units: (typeof xlsxPivotDateUnits)[number][];
}
export interface XlsxPivotNumberGroup {
  /** Zero-based numeric row/column field; records retain original numbers. */
  field: number;
  /** Null follows the source minimum on refresh. */
  start: number | null;
  /** Null follows the source maximum on refresh. */
  end: number | null;
  interval: number;
}
export interface XlsxPivotFilter {
  field: number;
  /** True places this field in the report area; false filters members in place. */
  report: boolean;
  /** Null includes all source members; an empty array selects none. */
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
  rowFields: number[];
  columnFields: number[];
  recordCount: number;
  filteredCount: number;
  filterItems: { value: CellValue; label: string }[][];
  baseItems: { value: CellValue; label: string }[][];
  groups: number;
  truncated: boolean;
  columnMembers: {
    members: CellValue[];
    formats: string[];
    subtotal: boolean;
  }[];
  columnTotals: CellValue[][];
  rows: {
    subtotal: boolean;
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
    recovery?: Omit<XlsxPivotSettings, "sourceSheet">;
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
function pivotBounds(source: unknown, sourceWidth = 64, limit = 65600) {
  try {
    return xlsxBounds(source, limit);
  } catch (error) {
    if (
      !text(source, 257) ||
      !/^(?:[_\\A-Za-z]|\P{ASCII})(?:[_\\.A-Za-z0-9]|\P{ASCII})*(?:\[\])?$/u.test(
        source,
      )
    )
      throw error;
    if (!integer(sourceWidth, 1, 64))
      throw new Error("Invalid pivot source width");
    return {
      top: 1,
      bottom: Math.floor(65536 / sourceWidth) + 1,
      left: 1,
      right: sourceWidth,
    };
  }
}

export function checkXlsxPivotSettings(value: unknown): void {
  checkPivotSettings(value);
}

function checkPivotSettings(value: unknown, sourceWidth?: number): void {
  const settings = record(value),
    bounds = pivotBounds(settings.source, sourceWidth),
    width = bounds.right - bounds.left + 1;
  if (
    !fields(settings, [
      "sourceSheet",
      "source",
      "rows",
      "columns",
      "filters",
      "subtotals",
      "numberGroups",
      "dateGroups",
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
    !Array.isArray(settings.subtotals) ||
    settings.subtotals.length > 14 ||
    new Set(settings.subtotals).size !== settings.subtotals.length ||
    !Array.isArray(settings.numberGroups) ||
    settings.numberGroups.length > 16 ||
    !Array.isArray(settings.dateGroups) ||
    settings.dateGroups.length + settings.numberGroups.length > 16 ||
    !Array.isArray(settings.values) ||
    !settings.values.length ||
    settings.values.length > 8
  )
    throw new Error("Invalid pivot settings");
  const outerFields = [
    ...settings.rows.slice(0, -1),
    ...settings.columns.slice(0, -1),
  ];
  const names = new Set<string>();
  const axes = new Set([...settings.rows, ...settings.columns]);
  const grouped = new Set<number>();
  for (const value of settings.numberGroups) {
    const group = record(value);
    if (
      !fields(group, ["field", "start", "end", "interval"]) ||
      typeof group.field !== "number" ||
      !integer(group.field, 0, width - 1) ||
      !axes.has(group.field) ||
      grouped.has(group.field) ||
      (group.start !== null &&
        (typeof group.start !== "number" || !Number.isFinite(group.start))) ||
      (group.end !== null &&
        (typeof group.end !== "number" || !Number.isFinite(group.end))) ||
      typeof group.interval !== "number" ||
      !Number.isFinite(group.interval) ||
      group.interval <= 0 ||
      (typeof group.start === "number" &&
        (!Number.isFinite(group.start + group.interval) ||
          group.start + group.interval <= group.start)) ||
      (typeof group.start === "number" &&
        typeof group.end === "number" &&
        (group.start >= group.end ||
          !Number.isFinite(group.end - group.start) ||
          Math.ceil((group.end - group.start) / group.interval) > 4094))
    )
      throw new Error("Invalid pivot numeric group");
    grouped.add(group.field);
  }
  let groupedUnits = settings.numberGroups.length,
    rowDepth = settings.rows.length,
    columnDepth = settings.columns.length;
  for (const value of settings.dateGroups) {
    const group = record(value);
    if (
      !fields(group, ["field", "units"]) ||
      typeof group.field !== "number" ||
      !integer(group.field, 0, width - 1) ||
      !axes.has(group.field) ||
      grouped.has(group.field) ||
      !Array.isArray(group.units) ||
      !group.units.length ||
      group.units.length > 4
    )
      throw new Error("Invalid pivot calendar group");
    grouped.add(group.field);
    const ranks = group.units.map((unit) =>
      xlsxPivotDateUnits.findIndex((candidate) => candidate === unit),
    );
    if (ranks.some((rank, i) => rank < 0 || (i > 0 && rank <= ranks[i - 1]!)))
      throw new Error("Invalid pivot calendar unit order");
    groupedUnits += group.units.length;
    if (settings.rows.includes(group.field)) rowDepth += group.units.length - 1;
    if (settings.columns.includes(group.field))
      columnDepth += group.units.length - 1;
    if (group.units.length > 1) outerFields.push(group.field);
  }
  if (
    groupedUnits > 16 ||
    rowDepth > 8 ||
    columnDepth > 8 ||
    settings.subtotals.some((field) => !outerFields.includes(field))
  )
    throw new Error("Invalid expanded pivot axes or subtotals");
  let units = 0;
  const filterFields = new Set<number>();
  for (const value of settings.filters) {
    const filter = record(value);
    if (
      !fields(filter, ["field", "values", "report"]) ||
      typeof filter.field !== "number" ||
      !integer(filter.field, 0, width - 1) ||
      filterFields.has(filter.field) ||
      typeof filter.report !== "boolean" ||
      (filter.report && axes.has(filter.field)) ||
      !(
        filter.values === null ||
        (Array.isArray(filter.values) && filter.values.length <= 4096)
      )
    )
      throw new Error("Invalid pivot member filter");
    filterFields.add(filter.field);
    if (Array.isArray(filter.values)) {
      const seen = new Set<string>();
      for (const value of filter.values) {
        const key = filterValue(value);
        units += key.length;
        if (seen.has(key) || units > 1048576)
          throw new Error("Duplicate or excessive pivot filter values");
        seen.add(key);
      }
    }
  }
  for (const item of settings.values) {
    const value = record(item);
    if (
      !fields(value, [
        "field",
        "aggregate",
        "name",
        "showDataAs",
        "baseField",
        "baseItem",
      ]) ||
      !integer(value.field, 0, width - 1) ||
      !xlsxPivotAggregates.some((kind) => kind === value.aggregate) ||
      !xlsxPivotValueModes.some((mode) => mode === value.showDataAs) ||
      (xlsxPivotBaseModes.some((mode) => mode === value.showDataAs)
        ? !integer(value.baseField, 0, width - 1) ||
          ![...settings.rows, ...settings.columns].includes(value.baseField)
        : value.baseField !== null) ||
      !text(value.name, 255) ||
      !value.name.trim() ||
      names.has(value.name.toLowerCase())
    )
      throw new Error("Invalid pivot value field");
    if (xlsxPivotCompareModes.some((mode) => mode === value.showDataAs)) {
      if (value.baseItem !== "previous" && value.baseItem !== "next")
        filterValue(value.baseItem);
    } else if (value.baseItem !== null)
      throw new Error("Unexpected pivot base item");
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
    sourceRows = settings.rows as number[],
    sourceColumns = settings.columns as number[],
    dates = settings.dateGroups as XlsxPivotDateGroup[],
    filters = settings.filters as XlsxPivotFilter[],
    subtotals = settings.subtotals as number[],
    values = settings.values as XlsxPivotValue[],
    bounds = pivotBounds(
      settings.source,
      Array.isArray(result.fields)
        ? result.fields.length -
            dates.reduce((sum, group) => sum + group.units.length - 1, 0)
        : 0,
    );
  const width = bounds.right - bounds.left + 1;
  checkPivotSettings(result.settings, width);
  const fieldCount =
    width + dates.reduce((sum, group) => sum + group.units.length - 1, 0);
  const subtotalAxes = [new Set<number>(), new Set<number>()];
  for (const [index, input, source] of [
    [0, result.rowFields, sourceRows],
    [1, result.columnFields, sourceColumns],
  ] as const) {
    if (
      !Array.isArray(input) ||
      input.length > 8 ||
      input.some((field) => !integer(field, 0, fieldCount - 1)) ||
      new Set(input).size !== input.length
    )
      throw new Error("Invalid pivot axis fields");
    const axis = input as number[];
    let at = 0;
    for (const field of source) {
      const count =
        dates.find((group) => group.field === field)?.units.length ?? 1;
      if (
        axis[at + count - 1] !== field ||
        axis.slice(at, at + count - 1).some((item) => item < width)
      )
        throw new Error("Invalid derived pivot axis");
      if (subtotals.includes(field))
        for (let i = at; i < at + count && i < axis.length - 1; i++)
          subtotalAxes[index]!.add(axis[i]!);
      at += count;
    }
    if (at !== axis.length) throw new Error("Invalid pivot axis depth");
  }
  const rows = result.rowFields as number[],
    columns = result.columnFields as number[];
  if (new Set([...rows, ...columns]).size !== rows.length + columns.length)
    throw new Error("Duplicate pivot axis field");
  if (
    !integer(result.revision, 0, 2147483647) ||
    !Array.isArray(result.fields) ||
    result.fields.length !== fieldCount ||
    result.fields.some((field) => !text(field, 255)) ||
    new Set(result.fields).size !== result.fields.length ||
    !integer(result.recordCount, 1, bounds.bottom - bounds.top) ||
    !integer(result.filteredCount, 0, Number(result.recordCount)) ||
    !integer(
      result.groups,
      Number(result.filteredCount) > 0 ? 1 : 0,
      Math.min(4096, Number(result.filteredCount) * rows.length),
    ) ||
    result.truncated !== Number(result.groups) > 20 ||
    !Array.isArray(result.rows) ||
    result.rows.length !== Math.min(20, Number(result.groups)) ||
    !Array.isArray(result.total) ||
    result.total.length !== values.length ||
    !result.total.every(cellValue) ||
    !Array.isArray(result.columnMembers) ||
    result.columnMembers.length > 4096 ||
    result.columnMembers.length >
      Number(result.filteredCount) * columns.length ||
    (columns.length === 0
      ? result.columnMembers.length !== 0
      : (result.columnMembers.length === 0) !== (result.filteredCount === 0)) ||
    !Array.isArray(result.columnTotals) ||
    result.columnTotals.length !==
      (columns.length ? result.columnMembers.length : 1) ||
    !Array.isArray(result.filterItems) ||
    result.filterItems.length !== filters.length ||
    !Array.isArray(result.baseItems) ||
    result.baseItems.length !== values.length ||
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
  for (const [at, items] of result.baseItems.entries()) {
    if (
      !Array.isArray(items) ||
      items.length > 4096 ||
      (xlsxPivotCompareModes.includes(values[at]!.showDataAs)
        ? !items.length
        : items.length !== 0)
    )
      throw new Error("Invalid pivot base items");
    const seen = new Set<string>();
    for (const value of items) {
      const item = record(value),
        key = filterValue(item.value);
      if (
        !fields(item, ["value", "label"]) ||
        seen.has(key) ||
        !(item.label === "" || text(item.label, 32767))
      )
        throw new Error("Invalid pivot base item");
      seen.add(key);
    }
  }
  for (const item of result.rows) {
    const row = record(item);
    if (
      !Array.isArray(row.members) ||
      row.members.length < 1 ||
      row.members.length > rows.length ||
      row.subtotal !== row.members.length < rows.length ||
      (row.subtotal && !subtotalAxes[0]!.has(rows[row.members.length - 1]!)) ||
      !row.members.every(cellValue) ||
      !Array.isArray(row.formats) ||
      row.formats.length !== row.members.length ||
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
      column.members.length < 1 ||
      column.members.length > columns.length ||
      column.subtotal !== column.members.length < columns.length ||
      (column.subtotal &&
        !subtotalAxes[1]!.has(columns[column.members.length - 1]!)) ||
      !column.members.every(cellValue) ||
      !Array.isArray(column.formats) ||
      column.formats.length !== column.members.length ||
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
    if (pivot.source !== null) pivotBounds(pivot.source, 64, 17179869184);
    if (pivot.settings !== null) {
      checkXlsxPivotSettings(pivot.settings);
      const settings = record(pivot.settings);
      if (
        settings.sourceSheet !== pivot.sourceSheet ||
        settings.source !== pivot.source
      )
        throw new Error("Pivot source disagrees with settings");
    }
    if (pivot.recovery !== undefined) {
      const recovery = record(pivot.recovery);
      if (
        pivot.settings !== null ||
        pivot.sourceSheet !== null ||
        "sourceSheet" in recovery ||
        recovery.source !== pivot.source
      )
        throw new Error("Invalid missing-source pivot recovery");
      checkXlsxPivotSettings({ ...recovery, sourceSheet: "recovery" });
    }
    parts.add(pivot.part);
  }
  return value as XlsxPivots;
}
