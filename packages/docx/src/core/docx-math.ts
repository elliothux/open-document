import { record, integer } from "@open-document/wasm/abi/validation";
import {
  latexSourceUnits,
  mathFontUnits,
  mathTextUnits,
} from "@open-document/wasm/engine-source";

import type { MathFormat } from "@open-document/wasm/abi/math";
export type { MathFormat } from "@open-document/wasm/abi/math";
export interface DocxMathValue {
  latex: string;
  format?: MathFormat;
}
export type DocxMathEdit =
  | (DocxMathValue & { action: "insert"; display?: boolean })
  | (DocxMathValue & { action: "update"; id: number })
  | { action: "delete"; id: number };
export interface DocxMathExpressions {
  revision: number;
  items: {
    id: number;
    latex: string;
    reason: string;
    format: MathFormat | null;
  }[];
}
export interface DocxFractionValue {
  numerator: string;
  denominator: string;
  /** Omit to inherit on insertion or preserve an existing fraction's appearance. */
  format?: MathFormat;
}
export type DocxFractionEdit =
  | (DocxFractionValue & { action: "insert" })
  | (DocxFractionValue & { action: "update"; id: number })
  | { action: "delete"; id: number };
export interface DocxMathFractions {
  revision: number;
  items: {
    id: number;
    numerator: string;
    denominator: string;
    reason: string;
    format: MathFormat | null;
  }[];
}
export interface DocxScriptValue {
  base: string;
  subscript: string;
  superscript: string;
  /** Empty indices are absent; omit format to inherit or preserve appearance. */
  format?: MathFormat;
}
export type DocxScriptEdit =
  | (DocxScriptValue & { action: "insert" })
  | (DocxScriptValue & { action: "update"; id: number })
  | { action: "delete"; id: number };
export interface DocxMathScripts {
  revision: number;
  items: {
    id: number;
    base: string;
    subscript: string;
    superscript: string;
    reason: string;
    format: MathFormat | null;
  }[];
}

function fractionText(value: unknown): value is string {
  return (
    typeof value === "string" &&
    value.length > 0 &&
    value.length <= mathTextUnits &&
    value.isWellFormed() &&
    Array.from(value).every(
      (c) =>
        c.codePointAt(0)! >= 32 &&
        c !== "\u2028" &&
        c !== "\u2029" &&
        c !== "\ufffe" &&
        c !== "\uffff",
    )
  );
}
function fractionFormat(value: unknown): boolean {
  const format = record(value);
  return (
    Object.keys(format).length === 3 &&
    fractionText(format.family) &&
    format.family.trim().length > 0 &&
    format.family.length <= mathFontUnits &&
    typeof format.size === "number" &&
    Number.isFinite(format.size) &&
    format.size >= 0.5 &&
    format.size <= 409 &&
    Number.isInteger(format.size * 2) &&
    typeof format.color === "string" &&
    /^[0-9a-f]{6}$/i.test(format.color)
  );
}
export function checkDocxFractionEdit(value: unknown): void {
  const edit = record(value);
  const insert = edit.action === "insert",
    remove = edit.action === "delete";
  const keys = remove
    ? ["action", "id"]
    : insert
      ? ["action", "numerator", "denominator"]
      : ["action", "id", "numerator", "denominator"];
  const formatted = !remove && Object.hasOwn(edit, "format");
  if (formatted) keys.push("format");
  if (
    typeof edit.action !== "string" ||
    !["insert", "update", "delete"].includes(edit.action) ||
    Object.keys(edit).length !== keys.length ||
    Object.keys(edit).some((key) => !keys.includes(key)) ||
    (!insert && !integer(edit.id, 0, 2147483647)) ||
    (formatted && !fractionFormat(edit.format)) ||
    (!remove &&
      (!fractionText(edit.numerator) ||
        !fractionText(edit.denominator) ||
        edit.numerator.length + edit.denominator.length > mathTextUnits))
  )
    throw new Error("Invalid fraction edit");
}
export function checkDocxScriptEdit(value: unknown): void {
  const edit = record(value);
  const insert = edit.action === "insert",
    remove = edit.action === "delete";
  const keys = ["action"];
  if (!insert) keys.push("id");
  if (!remove) keys.push("base", "subscript", "superscript");
  const formatted = !remove && Object.hasOwn(edit, "format");
  if (formatted) keys.push("format");
  if (
    typeof edit.action !== "string" ||
    !["insert", "update", "delete"].includes(edit.action) ||
    Object.keys(edit).length !== keys.length ||
    Object.keys(edit).some((key) => !keys.includes(key)) ||
    (!insert && !integer(edit.id, 0, 2147483647)) ||
    (formatted && !fractionFormat(edit.format)) ||
    (!remove &&
      (!fractionText(edit.base) ||
        (edit.subscript !== "" && !fractionText(edit.subscript)) ||
        (edit.superscript !== "" && !fractionText(edit.superscript)) ||
        (!edit.subscript && !edit.superscript) ||
        edit.base.length + edit.subscript.length + edit.superscript.length >
          mathTextUnits))
  )
    throw new Error("Invalid script edit");
}
export function checkDocxMathEdit(value: unknown): void {
  const edit = record(value),
    insert = edit.action === "insert",
    remove = edit.action === "delete";
  const keys = ["action"];
  if (insert && Object.hasOwn(edit, "display")) {
    if (typeof edit.display !== "boolean")
      throw new Error("Invalid display placement");
    keys.push("display");
  }
  if (!insert) keys.push("id");
  if (!remove) keys.push("latex");
  const formatted = !remove && Object.hasOwn(edit, "format");
  if (formatted) keys.push("format");
  if (
    typeof edit.action !== "string" ||
    !["insert", "update", "delete"].includes(edit.action) ||
    Object.keys(edit).length !== keys.length ||
    Object.keys(edit).some((key) => !keys.includes(key)) ||
    (!insert && !integer(edit.id, 0, 2147483647)) ||
    (formatted && !fractionFormat(edit.format)) ||
    (!remove &&
      (typeof edit.latex !== "string" ||
        !edit.latex.trim().length ||
        edit.latex.length > latexSourceUnits ||
        !edit.latex.isWellFormed() ||
        Array.from(edit.latex).some(
          (c) =>
            c.codePointAt(0)! < 32 ||
            ["\u2028", "\u2029", "\ufffe", "\uffff"].includes(c),
        )))
  )
    throw new Error("Invalid math expression edit");
}
