import { record, integer } from "./validation.js";
import { checkXlsxCellFormat, type XlsxCellFormat } from "./xlsx-format.js";
import { validationOperators } from "./xlsx-validation.js";

export interface XlsxConditionalFormat {
  kind:
    | "cellIs"
    | "expression"
    | "colorScale"
    | "dataBar"
    | "iconSet"
    | "top10"
    | "aboveAverage"
    | "duplicateValues"
    | "uniqueValues"
    | "containsBlanks"
    | "notContainsBlanks"
    | "containsErrors"
    | "notContainsErrors"
    | "containsText"
    | "notContainsText"
    | "beginsWith"
    | "endsWith"
    | "timePeriod";
  operator: "" | (typeof validationOperators)[number];
  formula1: string;
  formula2: string;
  stopIfTrue: boolean;
  format: XlsxCellFormat;
  stops?: XlsxConditionalStop[];
  bar?: XlsxDataBar;
  icons?: XlsxIconSet;
  rank?: XlsxConditionalRank;
  average?: XlsxConditionalAverage;
  text?: string;
  timePeriod?: (typeof conditionalDatePeriods)[number];
}
export const conditionalDatePeriods = [
  "yesterday",
  "today",
  "tomorrow",
  "last7Days",
  "lastWeek",
  "thisWeek",
  "nextWeek",
  "lastMonth",
  "thisMonth",
  "nextMonth",
] as const;
export interface XlsxConditionalRank {
  rank: number;
  percent: boolean;
  bottom: boolean;
}
export interface XlsxConditionalAverage {
  above: boolean;
  equal: boolean;
  stdDev: number;
}
export interface XlsxConditionalThreshold {
  kind: "min" | "max" | "num" | "percent" | "percentile" | "formula";
  value: string;
}
export interface XlsxConditionalStop extends XlsxConditionalThreshold {
  color: string;
}
export interface XlsxDataBar {
  minimum: XlsxConditionalThreshold;
  maximum: XlsxConditionalThreshold;
  color: string;
  showValue: boolean;
  minLength: number;
  maxLength: number;
}
export const conditionalIconSets = [
  "3Arrows",
  "3TrafficLights1",
  "3Flags",
  "3ArrowsGray",
  "4Arrows",
  "4ArrowsGray",
  "5Arrows",
  "5ArrowsGray",
  "3Signs",
  "3Symbols",
  "3Symbols2",
  "3TrafficLights2",
  "4Rating",
  "4RedToBlack",
  "4TrafficLights",
  "5Rating",
  "5Quarters",
] as const;
export interface XlsxIconThreshold extends XlsxConditionalThreshold {
  greaterOrEqual: boolean;
}
export interface XlsxIconSet {
  kind: (typeof conditionalIconSets)[number];
  reverse: boolean;
  showValue: boolean;
  percent: boolean;
  thresholds: XlsxIconThreshold[];
}
export const conditionalThresholds = [
  "min",
  "max",
  "num",
  "percent",
  "percentile",
  "formula",
] as const;
export interface XlsxConditionalRule {
  priority: number;
  ranges: string;
  rule: XlsxConditionalFormat;
  readOnlyReason: string;
}
export interface XlsxConditionalState {
  rules: XlsxConditionalRule[];
  readOnlyReason: string;
}
export function checkXlsxConditionalFormat(value: unknown): void {
  const rule = record(value);
  if (
    !Object.keys(rule).every((k) =>
      [
        "kind",
        "operator",
        "formula1",
        "formula2",
        "stopIfTrue",
        "format",
        "stops",
        "bar",
        "icons",
        "rank",
        "average",
        "text",
        "timePeriod",
      ].includes(k),
    ) ||
    !(
      ([
        "expression",
        "colorScale",
        "dataBar",
        "iconSet",
        "top10",
        "aboveAverage",
        "duplicateValues",
        "uniqueValues",
        "containsBlanks",
        "notContainsBlanks",
        "containsErrors",
        "notContainsErrors",
        "containsText",
        "notContainsText",
        "beginsWith",
        "endsWith",
        "timePeriod",
      ].includes(String(rule.kind)) &&
        rule.operator === "") ||
      (rule.kind === "cellIs" &&
        validationOperators.some((o) => o === rule.operator))
    ) ||
    typeof rule.stopIfTrue !== "boolean"
  )
    throw new Error("Invalid conditional format kind or operator");
  if (rule.kind !== "iconSet" && rule.icons !== undefined)
    throw new Error("Only icon set rules have icon settings");
  const textRule = [
    "containsText",
    "notContainsText",
    "beginsWith",
    "endsWith",
  ].includes(String(rule.kind));
  if (!textRule && rule.text !== undefined)
    throw new Error("Only text rules have text settings");
  if (
    rule.kind === "timePeriod"
      ? !conditionalDatePeriods.some((period) => period === rule.timePeriod)
      : rule.timePeriod !== undefined
  )
    throw new Error("Invalid conditional date period");
  for (const key of ["formula1", "formula2", ...(textRule ? ["text"] : [])]) {
    const text = rule[key];
    if (
      typeof text !== "string" ||
      text.length > 8192 ||
      !text.isWellFormed() ||
      Array.from(text).some((c) => {
        const n = c.codePointAt(0)!;
        return (
          (n < 32 && ![9, 10, 13].includes(n)) || n === 65534 || n === 65535
        );
      })
    )
      throw new Error("Invalid conditional formula or text");
  }
  if (rule.kind === "iconSet") {
    const icons = record(rule.icons);
    if (
      rule.operator !== "" ||
      rule.formula1 !== "" ||
      rule.formula2 !== "" ||
      rule.stopIfTrue ||
      Object.keys(record(rule.format)).length ||
      rule.stops !== undefined ||
      rule.bar !== undefined ||
      rule.rank !== undefined ||
      rule.average !== undefined ||
      Object.keys(icons).length !== 5 ||
      !conditionalIconSets.some((kind) => kind === icons.kind) ||
      typeof icons.reverse !== "boolean" ||
      typeof icons.showValue !== "boolean" ||
      typeof icons.percent !== "boolean" ||
      !Array.isArray(icons.thresholds) ||
      icons.thresholds.length !== Number(String(icons.kind)[0])
    )
      throw new Error("Invalid conditional icon set");
    for (const value of icons.thresholds) {
      const threshold = record(value);
      if (
        Object.keys(threshold).length !== 3 ||
        typeof threshold.greaterOrEqual !== "boolean"
      )
        throw new Error("Invalid conditional icon threshold");
      checkConditionalStop({
        kind: threshold.kind,
        value: threshold.value,
        color: "000000",
      });
    }
    return;
  }
  if (rule.kind === "top10" || rule.kind === "aboveAverage") {
    if (
      rule.formula1 !== "" ||
      rule.formula2 !== "" ||
      rule.stops !== undefined ||
      rule.bar !== undefined
    )
      throw new Error("Invalid statistical conditional rule");
    if (rule.kind === "top10") {
      const rank = record(rule.rank);
      if (
        rule.average !== undefined ||
        Object.keys(rank).length !== 3 ||
        typeof rank.percent !== "boolean" ||
        typeof rank.bottom !== "boolean" ||
        !integer(rank.rank, 1, rank.percent ? 100 : 1000)
      )
        throw new Error("Invalid conditional rank");
    } else {
      const average = record(rule.average);
      if (
        rule.rank !== undefined ||
        Object.keys(average).length !== 3 ||
        typeof average.above !== "boolean" ||
        typeof average.equal !== "boolean" ||
        !integer(average.stdDev, 0, 3)
      )
        throw new Error("Invalid conditional average");
    }
    checkXlsxCellFormat(rule.format);
    return;
  }
  if (rule.rank !== undefined || rule.average !== undefined)
    throw new Error("Only statistical rules have rank or average settings");
  if (
    [
      "duplicateValues",
      "uniqueValues",
      "containsBlanks",
      "notContainsBlanks",
      "containsErrors",
      "notContainsErrors",
    ].includes(String(rule.kind)) ||
    textRule ||
    rule.kind === "timePeriod"
  ) {
    if (
      rule.formula1 !== "" ||
      rule.formula2 !== "" ||
      rule.bar !== undefined ||
      rule.stops !== undefined
    )
      throw new Error("Invalid built-in conditional settings");
    checkXlsxCellFormat(rule.format);
    return;
  }
  if (rule.kind === "colorScale" || rule.kind === "dataBar") {
    if (
      rule.formula1 !== "" ||
      rule.formula2 !== "" ||
      rule.stopIfTrue !== false ||
      Object.keys(record(rule.format)).length
    )
      throw new Error("Invalid visual conditional format settings");
    let stops: unknown[];
    if (rule.kind === "colorScale") {
      if (
        rule.bar !== undefined ||
        !Array.isArray(rule.stops) ||
        ![2, 3].includes(rule.stops.length)
      )
        throw new Error("Invalid color scale settings");
      stops = rule.stops;
    } else {
      const bar = record(rule.bar);
      if (
        rule.stops !== undefined ||
        !Object.keys(bar).every((k) =>
          [
            "minimum",
            "maximum",
            "color",
            "showValue",
            "minLength",
            "maxLength",
          ].includes(k),
        ) ||
        typeof bar.showValue !== "boolean" ||
        !integer(bar.minLength, 0, 100) ||
        !integer(bar.maxLength, 0, 100) ||
        Number(bar.minLength) > Number(bar.maxLength)
      )
        throw new Error("Invalid data bar settings");
      stops = [bar.minimum, bar.maximum].map((value) => {
        const threshold = record(value);
        if (!Object.keys(threshold).every((k) => ["kind", "value"].includes(k)))
          throw new Error("Invalid data bar threshold");
        return { ...threshold, color: bar.color };
      });
    }
    for (const value of stops) checkConditionalStop(value);
    return;
  }
  if (rule.stops !== undefined || rule.bar !== undefined)
    throw new Error("Highlight rules have no visual settings");
  if (
    rule.formula1 === "" ||
    (rule.operator === "between" || rule.operator === "notBetween"
      ? rule.formula2 === ""
      : rule.formula2 !== "")
  )
    throw new Error("Missing conditional formula");
  checkXlsxCellFormat(rule.format);
}
function checkConditionalStop(value: unknown): void {
  const stop = record(value);
  if (
    !Object.keys(stop).every((k) => ["kind", "value", "color"].includes(k)) ||
    !conditionalThresholds.some((k) => k === stop.kind) ||
    typeof stop.value !== "string" ||
    stop.value.length > 8192 ||
    !stop.value.isWellFormed() ||
    Array.from(stop.value).some((c) => {
      const n = c.codePointAt(0)!;
      return (n < 32 && ![9, 10, 13].includes(n)) || n === 65534 || n === 65535;
    }) ||
    typeof stop.color !== "string" ||
    !/^[0-9a-fA-F]{6}$/u.test(stop.color)
  )
    throw new Error("Invalid color scale stop");
  if (stop.kind === "min" || stop.kind === "max") {
    if (stop.value !== "")
      throw new Error("Automatic color stops have no value");
  } else if (stop.kind === "formula") {
    if (!stop.value) throw new Error("Missing color scale formula");
  } else if (
    !stop.value.trim() ||
    !Number.isFinite(Number(stop.value)) ||
    (stop.kind !== "num" &&
      (Number(stop.value) < 0 || Number(stop.value) > 100))
  )
    throw new Error("Invalid color scale threshold");
}
export function xlsxConditionalState(value: unknown): XlsxConditionalState {
  const state = record(value);
  if (
    typeof state.readOnlyReason !== "string" ||
    !Array.isArray(state.rules) ||
    state.rules.length > 4096
  )
    throw new Error("Invalid conditional formatting query");
  let units = 0;
  const seen = new Set<number>();
  for (const item of state.rules) {
    const rule = record(item);
    if (
      typeof rule.priority !== "number" ||
      !integer(rule.priority, 1, 2147483647) ||
      seen.has(rule.priority) ||
      typeof rule.ranges !== "string" ||
      !rule.ranges ||
      rule.ranges.length > 262144 ||
      typeof rule.readOnlyReason !== "string"
    )
      throw new Error("Invalid conditional rule query");
    seen.add(rule.priority);
    checkXlsxConditionalFormat(rule.rule);
    const settings = record(rule.rule);
    units +=
      rule.ranges.length +
      String(settings.formula1).length +
      String(settings.formula2).length;
    if (Array.isArray(settings.stops))
      for (const item of settings.stops)
        units += String(record(item).value).length;
    if (settings.bar !== undefined) {
      const bar = record(settings.bar);
      units +=
        String(record(bar.minimum).value).length +
        String(record(bar.maximum).value).length;
    }
    if (settings.icons !== undefined) {
      const icons = record(settings.icons);
      if (Array.isArray(icons.thresholds))
        for (const threshold of icons.thresholds)
          units += String(record(threshold).value).length;
    }
  }
  if (units > 1048576) throw new Error("Conditional query exceeds text budget");
  return value as XlsxConditionalState;
}
