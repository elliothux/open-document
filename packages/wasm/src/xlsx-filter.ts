import { record, integer } from "./validation.js";

export const xlsxRelativeDatePeriods = [
  "yesterday",
  "today",
  "tomorrow",
  "lastWeek",
  "thisWeek",
  "nextWeek",
  "lastMonth",
  "thisMonth",
  "nextMonth",
  "lastQuarter",
  "thisQuarter",
  "nextQuarter",
  "lastYear",
  "thisYear",
  "nextYear",
  "yearToDate",
] as const;
export interface XlsxRelativeDateFilter {
  kind: "relativeDate";
  column: number;
  period: (typeof xlsxRelativeDatePeriods)[number];
}

/** Supply local calendar components; the core computes date intervals. */
export function spreadsheetDate(value?: string): string {
  if (value === undefined) {
    const now = new Date();
    value =
      String(now.getFullYear()).padStart(4, "0") +
      "-" +
      String(now.getMonth() + 1).padStart(2, "0") +
      "-" +
      String(now.getDate()).padStart(2, "0");
  }
  if (
    typeof value !== "string" ||
    !/^\d{4}-\d{2}-\d{2}$/.test(value) ||
    value.startsWith("0000")
  )
    throw new Error("Invalid current calendar date");
  const parsed = new Date(value + "T00:00:00Z");
  if (
    !Number.isFinite(parsed.getTime()) ||
    parsed.toISOString().slice(0, 10) !== value
  )
    throw new Error("Invalid current calendar date");
  return value;
}

export interface XlsxFilterValues {
  kind: "values";
  /** One-based worksheet column. Values match trimmed, formatted labels without case. */
  column: number;
  values: string[];
  blank: boolean;
}
export type XlsxFilterOperator =
  | "equal"
  | "notEqual"
  | "greaterThan"
  | "greaterThanOrEqual"
  | "lessThan"
  | "lessThanOrEqual";
export interface XlsxFilterCondition {
  operator: XlsxFilterOperator;
  /** Numeric comparisons use current values; text supports *, ? and ~ escaping. */
  value: string;
}
export interface XlsxCustomFilter {
  kind: "custom";
  column: number;
  conditions: XlsxFilterCondition[];
  /** True joins the conditions with AND, false with OR. */
  all: boolean;
}
export interface XlsxRankFilter {
  kind: "rank";
  column: number;
  /** 1..500 items or 1..100 percent of numeric records; boundary ties are included. */
  value: number;
  top: boolean;
  percent: boolean;
}
export interface XlsxAverageFilter {
  kind: "average";
  column: number;
  /** Strictly above or below the mean of all numeric records, including hidden rows. */
  above: boolean;
}
export interface XlsxDateFilter {
  kind: "dates";
  column: number;
  /** Calendar prefixes from YYYY through YYYY-MM-DDTHH:mm:ss, without a time zone. */
  groups: string[];
  /** Trimmed labels for other cells, including text, general numbers and time-only formats. */
  values: string[];
  blank: boolean;
}
export interface XlsxCalendarFilter {
  kind: "calendar";
  column: number;
  /** A month (1..12) or quarter (1..4), across all years in the workbook date system. */
  unit: "month" | "quarter";
  /** Numeric serials match regardless of display format; other cell types do not match. */
  value: number;
}
export interface XlsxColorFilter {
  kind: "color";
  column: number;
  /** True filters the effective cell fill; false filters the effective font color. */
  cellColor: boolean;
  /** Six-digit RGB. Null means no fill or the automatic black font. */
  color: string | null;
}
export type XlsxFilterColumn =
  | XlsxFilterValues
  | XlsxCustomFilter
  | XlsxRankFilter
  | XlsxAverageFilter
  | XlsxDateFilter
  | XlsxCalendarFilter
  | XlsxRelativeDateFilter
  | XlsxColorFilter;
export interface XlsxFilterSettings {
  /** Explicit rectangle with a header in its first row. */
  range: string;
  columns: XlsxFilterColumn[];
}
export interface XlsxFilterState extends XlsxFilterSettings {
  reason: string;
  catalog: {
    column: number;
    title: string;
    blank: number;
    blankSelected: boolean;
    values: { value: string; count: number; selected: boolean }[];
  }[];
}

export function checkXlsxFilter(value: unknown): void {
  const settings = record(value);
  if (
    typeof settings.range !== "string" ||
    !settings.range ||
    settings.range.length > 64 ||
    !Array.isArray(settings.columns) ||
    settings.columns.length > 256
  )
    throw new Error("Invalid filter settings");
  const seen = new Set<number>();
  let units = 0;
  for (const value of settings.columns) {
    const column = record(value);
    if (!integer(column.column, 1, 16384) || seen.has(Number(column.column)))
      throw new Error("Invalid filter column");
    seen.add(Number(column.column));
    let values: unknown[];
    if (column.kind === "relativeDate") {
      if (
        typeof column.period !== "string" ||
        !xlsxRelativeDatePeriods.some((period) => period === column.period) ||
        Object.keys(column).some(
          (key) => !["kind", "column", "period"].includes(key),
        )
      )
        throw new Error("Invalid relative date filter");
      values = [];
    } else if (column.kind === "calendar") {
      if (
        (column.unit !== "month" && column.unit !== "quarter") ||
        !integer(column.value, 1, column.unit === "month" ? 12 : 4) ||
        Object.keys(column).some(
          (key) => !["kind", "column", "unit", "value"].includes(key),
        )
      )
        throw new Error("Invalid calendar filter");
      values = [];
    } else if (column.kind === "color") {
      if (
        typeof column.cellColor !== "boolean" ||
        (column.color !== null &&
          (typeof column.color !== "string" ||
            !/^[0-9a-f]{6}$/i.test(column.color))) ||
        Object.keys(column).some(
          (key) => !["kind", "column", "cellColor", "color"].includes(key),
        )
      )
        throw new Error("Invalid color filter");
      values = [];
    } else if (column.kind === "dates") {
      if (
        typeof column.blank !== "boolean" ||
        !Array.isArray(column.groups) ||
        !column.groups.length ||
        !Array.isArray(column.values) ||
        column.groups.length + column.values.length > 4096 ||
        new Set(column.groups).size !== column.groups.length ||
        new Set(column.values).size !== column.values.length ||
        column.groups.some(
          (group) =>
            typeof group !== "string" ||
            !/^\d{4}(?:-\d{2}(?:-\d{2}(?:T\d{2}(?::\d{2}(?::\d{2})?)?)?)?)?$/.test(
              group,
            ),
        ) ||
        Object.keys(column).some(
          (key) =>
            !["kind", "column", "groups", "values", "blank"].includes(key),
        )
      )
        throw new Error("Invalid date group filter");
      values = column.values;
      units += column.groups.reduce(
        (sum: number, group: string) => sum + group.length,
        0,
      );
      if (units > 1048576)
        throw new Error("Date filter groups exceed text budget");
    } else if (column.kind === "values") {
      if (
        typeof column.blank !== "boolean" ||
        !Array.isArray(column.values) ||
        column.values.length > 4096 ||
        new Set(column.values).size !== column.values.length ||
        Object.keys(column).some(
          (k) => !["kind", "column", "values", "blank"].includes(k),
        )
      )
        throw new Error("Invalid value filter");
      values = column.values;
    } else if (column.kind === "custom") {
      if (
        typeof column.all !== "boolean" ||
        !Array.isArray(column.conditions) ||
        column.conditions.length < 1 ||
        column.conditions.length > 2 ||
        Object.keys(column).some(
          (k) => !["kind", "column", "conditions", "all"].includes(k),
        )
      )
        throw new Error("Invalid custom filter");
      values = column.conditions.map((value) => {
        const condition = record(value);
        if (
          typeof condition.operator !== "string" ||
          ![
            "equal",
            "notEqual",
            "greaterThan",
            "greaterThanOrEqual",
            "lessThan",
            "lessThanOrEqual",
          ].includes(condition.operator) ||
          Object.keys(condition).some((k) => !["operator", "value"].includes(k))
        )
          throw new Error("Invalid filter condition");
        return condition.value;
      });
    } else if (column.kind === "average") {
      if (
        typeof column.above !== "boolean" ||
        Object.keys(column).some(
          (key) => !["kind", "column", "above"].includes(key),
        )
      )
        throw new Error("Invalid average filter");
      values = [];
    } else if (column.kind === "rank") {
      if (
        typeof column.top !== "boolean" ||
        typeof column.percent !== "boolean" ||
        !integer(column.value, 1, column.percent ? 100 : 500) ||
        Object.keys(column).some(
          (key) => !["kind", "column", "value", "top", "percent"].includes(key),
        )
      )
        throw new Error("Invalid rank filter");
      values = [];
    } else throw new Error("Invalid filter kind");
    for (const label of values) {
      if (
        typeof label !== "string" ||
        label.length > 32767 ||
        !label.isWellFormed() ||
        Array.from(label).some((character) => {
          const code = character.charCodeAt(0);
          return (
            (code < 32 && ![9, 10, 13].includes(code)) ||
            code === 65534 ||
            code === 65535
          );
        }) ||
        (units += label.length) > 1048576
      )
        throw new Error("Invalid filter label");
    }
  }
}

export function xlsxFilterState(value: unknown): XlsxFilterState {
  const state = record(value);
  checkXlsxFilter({ ...state, range: state.range || "A1:A2" });
  if (
    typeof state.reason !== "string" ||
    typeof state.range !== "string" ||
    !Array.isArray(state.columns) ||
    !Array.isArray(state.catalog) ||
    state.catalog.length > 2048
  )
    throw new Error("Invalid filter state");
  const seen = new Set<number>();
  let units = 0;
  for (const value of state.catalog) {
    const column = record(value);
    if (
      !integer(column.column, 1, 16384) ||
      seen.has(Number(column.column)) ||
      typeof column.title !== "string" ||
      column.title.length > 32767 ||
      !integer(column.blank, 0, 4095) ||
      typeof column.blankSelected !== "boolean" ||
      !Array.isArray(column.values) ||
      column.values.length > 8192
    )
      throw new Error("Invalid filter catalog");
    seen.add(Number(column.column));
    units += column.title.length;
    for (const value of column.values) {
      const entry = record(value);
      if (
        typeof entry.value !== "string" ||
        entry.value.length > 32767 ||
        !integer(entry.count, 0, 4095) ||
        typeof entry.selected !== "boolean"
      )
        throw new Error("Invalid filter choice");
      units += entry.value.length;
    }
    if (units > 2097152) throw new Error("Filter catalog exceeds text budget");
  }
  if (!state.range && (state.columns.length || state.catalog.length))
    throw new Error("Filter range is missing");
  return value as XlsxFilterState;
}
