import { record } from "@open-document/wasm/abi/validation";
import {
  xlsxValidationFormulaUnits,
  xlsxValidationMessageUnits,
  xlsxValidationTitleUnits,
} from "@open-document/wasm/engine-source";

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
    ["formula1", xlsxValidationFormulaUnits],
    ["formula2", xlsxValidationFormulaUnits],
    ["errorTitle", xlsxValidationTitleUnits],
    ["promptTitle", xlsxValidationTitleUnits],
    ["error", xlsxValidationMessageUnits],
    ["prompt", xlsxValidationMessageUnits],
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
