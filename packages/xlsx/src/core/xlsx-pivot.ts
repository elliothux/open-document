import type { CellValue } from "./xlsx.js";
import { cellValue } from "./xlsx-grid.js";
import { xlsxBounds } from "./xlsx-geometry.js";
import { integer, record } from "@open-document/wasm/abi/validation";
import {
  xlsxDefinedNameUnits,
  xlsxPivotDateUnitCount,
  xlsxPivotFieldsPerRole,
  xlsxPivotFilterUnits,
  xlsxPivotGroupUnits,
  xlsxPivotMembers,
  xlsxPivotSourceCells,
  xlsxPivotSourceColumns,
  xlsxPivotSubtotalFields,
  xlsxPivotValueNameUnits,
} from "@open-document/wasm/engine-source";

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
function pivotBounds(source: unknown, sourceWidth = xlsxPivotSourceColumns) {
  try {
    return xlsxBounds(source, xlsxPivotSourceCells + xlsxPivotSourceColumns);
  } catch (error) {
    if (
      !text(source, 257) ||
      !/^(?:[_\\A-Za-z]|\P{ASCII})(?:[_\\.A-Za-z0-9]|\P{ASCII})*(?:\[\])?$/u.test(
        source,
      )
    )
      throw error;
    if (!integer(sourceWidth, 1, xlsxPivotSourceColumns))
      throw new Error("Invalid pivot source width");
    return {
      top: 1,
      bottom: Math.floor(xlsxPivotSourceCells / sourceWidth) + 1,
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
    width > xlsxPivotSourceColumns ||
    (bounds.bottom - bounds.top) * width > xlsxPivotSourceCells ||
    !Array.isArray(settings.rows) ||
    !settings.rows.length ||
    settings.rows.length > xlsxPivotFieldsPerRole ||
    new Set(settings.rows).size !== settings.rows.length ||
    settings.rows.some((field) => !integer(field, 0, width - 1)) ||
    !Array.isArray(settings.columns) ||
    settings.columns.length > xlsxPivotFieldsPerRole ||
    settings.columns.some((field) => !integer(field, 0, width - 1)) ||
    new Set([...settings.rows, ...settings.columns]).size !==
      settings.rows.length + settings.columns.length ||
    !Array.isArray(settings.filters) ||
    settings.filters.length > xlsxPivotFieldsPerRole ||
    !Array.isArray(settings.subtotals) ||
    settings.subtotals.length > xlsxPivotSubtotalFields ||
    new Set(settings.subtotals).size !== settings.subtotals.length ||
    !Array.isArray(settings.numberGroups) ||
    settings.numberGroups.length > xlsxPivotGroupUnits ||
    !Array.isArray(settings.dateGroups) ||
    settings.dateGroups.length + settings.numberGroups.length >
      xlsxPivotGroupUnits ||
    !Array.isArray(settings.values) ||
    !settings.values.length ||
    settings.values.length > xlsxPivotFieldsPerRole
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
          Math.ceil((group.end - group.start) / group.interval) >
            xlsxPivotMembers - 2))
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
      group.units.length > xlsxPivotDateUnitCount
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
    groupedUnits > xlsxPivotGroupUnits ||
    rowDepth > xlsxPivotFieldsPerRole ||
    columnDepth > xlsxPivotFieldsPerRole ||
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
        (Array.isArray(filter.values) &&
          filter.values.length <= xlsxPivotMembers)
      )
    )
      throw new Error("Invalid pivot member filter");
    filterFields.add(filter.field);
    if (Array.isArray(filter.values)) {
      const seen = new Set<string>();
      for (const value of filter.values) {
        const key = filterValue(value);
        units += key.length;
        if (seen.has(key) || units > xlsxPivotFilterUnits)
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
      !text(value.name, xlsxPivotValueNameUnits) ||
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
    !text(edit.name, xlsxDefinedNameUnits) ||
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
