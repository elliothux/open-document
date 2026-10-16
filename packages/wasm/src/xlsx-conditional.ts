import { record, integer } from "./validation.js";
import { checkXlsxCellFormat, type XlsxCellFormat } from "./xlsx-format.js";
import { validationOperators } from "./xlsx-validation.js";

export interface XlsxConditionalFormat {
  kind: "cellIs" | "expression" | "colorScale";
  operator: "" | (typeof validationOperators)[number];
  formula1: string;
  formula2: string;
  stopIfTrue: boolean;
  format: XlsxCellFormat;
  stops?: XlsxConditionalStop[];
}
export interface XlsxConditionalStop {
  kind: "min" | "max" | "num" | "percent" | "percentile" | "formula";
  value: string;
  color: string;
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
      ].includes(k),
    ) ||
    !(
      (["expression", "colorScale"].includes(String(rule.kind)) &&
        rule.operator === "") ||
      (rule.kind === "cellIs" &&
        validationOperators.some((o) => o === rule.operator))
    ) ||
    typeof rule.stopIfTrue !== "boolean"
  )
    throw new Error("Invalid conditional format kind or operator");
  for (const key of ["formula1", "formula2"]) {
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
      throw new Error("Invalid conditional formula");
  }
  if (rule.kind === "colorScale") {
    if (
      rule.formula1 !== "" ||
      rule.formula2 !== "" ||
      rule.stopIfTrue !== false ||
      Object.keys(record(rule.format)).length ||
      !Array.isArray(rule.stops) ||
      ![2, 3].includes(rule.stops.length)
    )
      throw new Error("Invalid color scale settings");
    for (const value of rule.stops) {
      const stop = record(value);
      if (
        !Object.keys(stop).every((k) =>
          ["kind", "value", "color"].includes(k),
        ) ||
        !conditionalThresholds.some((k) => k === stop.kind) ||
        typeof stop.value !== "string" ||
        stop.value.length > 8192 ||
        !stop.value.isWellFormed() ||
        Array.from(stop.value).some((c) => {
          const n = c.codePointAt(0)!;
          return (
            (n < 32 && ![9, 10, 13].includes(n)) || n === 65534 || n === 65535
          );
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
    return;
  }
  if (rule.stops !== undefined)
    throw new Error("Highlight rules have no color scale stops");
  if (
    rule.formula1 === "" ||
    (rule.operator === "between" || rule.operator === "notBetween"
      ? rule.formula2 === ""
      : rule.formula2 !== "")
  )
    throw new Error("Missing conditional formula");
  checkXlsxCellFormat(rule.format);
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
  }
  if (units > 1048576) throw new Error("Conditional query exceeds text budget");
  return value as XlsxConditionalState;
}
