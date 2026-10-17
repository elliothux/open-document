import { record, integer } from "./validation.js";

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
export type XlsxFilterColumn = XlsxFilterValues | XlsxCustomFilter;
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
    if (column.kind === "values") {
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
