import { record, hasFields } from "./validation.js";

export const validationKinds = [
  "none",
  "whole",
  "decimal",
  "date",
  "time",
  "textLength",
  "list",
  "custom",
] as const;
export const validationOperators = [
  "between",
  "notBetween",
  "equal",
  "notEqual",
  "lessThan",
  "lessThanOrEqual",
  "greaterThan",
  "greaterThanOrEqual",
] as const;
export interface XlsxDataValidation {
  kind: (typeof validationKinds)[number];
  operator: (typeof validationOperators)[number];
  formula1: string;
  formula2: string;
  allowBlank: boolean;
  showErrorMessage: boolean;
  errorStyle: "stop" | "warning" | "information";
  errorTitle: string;
  error: string;
  showInputMessage: boolean;
  promptTitle: string;
  prompt: string;
  showDropDown: boolean;
}

export interface XlsxValidationState {
  rule: XlsxDataValidation | null;
  mixed: boolean;
  readOnlyReason: string;
  options: string[];
  optionsReason: string;
  promptVisible: boolean;
}

export function checkXlsxDataValidation(value: unknown): void {
  const rule = record(value);
  if (
    !validationKinds.some((k) => k === rule.kind) ||
    !validationOperators.some((o) => o === rule.operator) ||
    !["stop", "warning", "information"].includes(String(rule.errorStyle))
  )
    throw new Error("Invalid data validation type or operator");
  const booleans = [
    "allowBlank",
    "showErrorMessage",
    "showInputMessage",
    "showDropDown",
  ];
  if (!booleans.every((k) => typeof rule[k] === "boolean"))
    throw new Error("Invalid data validation flag");
  for (const [key, limit] of [
    ["formula1", 8192],
    ["formula2", 8192],
    ["errorTitle", 32],
    ["promptTitle", 32],
    ["error", 255],
    ["prompt", 255],
  ] as const) {
    const text = rule[key];
    if (
      typeof text !== "string" ||
      text.length > limit ||
      !text.isWellFormed() ||
      Array.from(text).some((character) => {
        const code = character.charCodeAt(0);
        return (
          (code < 32 && ![9, 10, 13].includes(code)) ||
          code === 65534 ||
          code === 65535
        );
      })
    )
      throw new Error("Invalid data validation text");
  }
  if (
    rule.kind !== "none" &&
    (rule.formula1 === "" ||
      (["between", "notBetween"].includes(String(rule.operator)) &&
        rule.kind !== "list" &&
        rule.kind !== "custom" &&
        rule.formula2 === ""))
  )
    throw new Error("Missing data validation formula");
}

export function xlsxValidationState(value: unknown): XlsxValidationState {
  const state = record(value);
  if (
    !hasFields(state, ["readOnlyReason", "optionsReason"], []) ||
    typeof state.mixed !== "boolean" ||
    typeof state.promptVisible !== "boolean" ||
    !Array.isArray(state.options) ||
    state.options.length > 4096 ||
    !state.options.every((o) => typeof o === "string" && o.isWellFormed()) ||
    state.options.reduce((sum, value) => sum + value.length, 0) > 1048576
  )
    throw new Error("Invalid data validation query");
  if (state.rule !== null) checkXlsxDataValidation(state.rule);
  return value as XlsxValidationState;
}
