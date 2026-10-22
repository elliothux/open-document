import { record, integer } from "./validation.js";
import { FoundationClipboardSession } from "./docx-clipboard.js";
import { editState, type EditState } from "./docx-format.js";

export interface DocxMathFormat {
  family: string;
  size: number;
  color: string;
}
export interface DocxFractionValue {
  numerator: string;
  denominator: string;
  /** Omit to inherit on insertion or preserve an existing fraction's appearance. */
  format?: DocxMathFormat;
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
    format: DocxMathFormat | null;
  }[];
}
export interface DocxScriptValue {
  base: string;
  subscript: string;
  superscript: string;
  /** Empty indices are absent; omit format to inherit or preserve appearance. */
  format?: DocxMathFormat;
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
    format: DocxMathFormat | null;
  }[];
}

function fractionText(value: unknown): value is string {
  return (
    typeof value === "string" &&
    value.length > 0 &&
    value.length <= 4096 &&
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
    format.family.length <= 255 &&
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
        edit.numerator.length + edit.denominator.length > 4096))
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
          4096))
  )
    throw new Error("Invalid script edit");
}
function checkMathCatalog(value: unknown, scripts: boolean): void {
  const catalog = record(value);
  if (
    Object.keys(catalog).length !== 2 ||
    !integer(catalog.revision, 0, 2147483647) ||
    !Array.isArray(catalog.items) ||
    catalog.items.length > 256
  )
    throw new Error("Invalid fraction catalog");
  const ids = new Set<number>();
  const names = scripts
    ? ["base", "subscript", "superscript"]
    : ["numerator", "denominator"];
  for (const item of catalog.items) {
    const fraction = record(item);
    const texts = names.map((name) => fraction[name]);
    if (
      Object.keys(fraction).length !== names.length + 3 ||
      typeof fraction.id !== "number" ||
      !integer(fraction.id, 0, 2147483647) ||
      typeof fraction.reason !== "string" ||
      !texts.every((text): text is string => typeof text === "string") ||
      texts.reduce((sum, text) => sum + text.length, 0) > 4096 ||
      ![...texts, fraction.reason].every((text) => text.isWellFormed()) ||
      ids.has(fraction.id) ||
      (fraction.reason
        ? fraction.format !== null
        : !fractionFormat(fraction.format))
    )
      throw new Error("Invalid fraction catalog item");
    if (!fraction.reason) {
      if (scripts)
        checkDocxScriptEdit({
          action: "update",
          id: fraction.id,
          base: fraction.base,
          subscript: fraction.subscript,
          superscript: fraction.superscript,
        });
      else
        checkDocxFractionEdit({
          action: "update",
          id: fraction.id,
          numerator: fraction.numerator,
          denominator: fraction.denominator,
        });
    }
    ids.add(fraction.id);
  }
}
export function docxMathFractions(value: unknown): DocxMathFractions {
  checkMathCatalog(value, false);
  return value as DocxMathFractions;
}
export function docxMathScripts(value: unknown): DocxMathScripts {
  checkMathCatalog(value, true);
  return value as DocxMathScripts;
}

export class FoundationMathSession extends FoundationClipboardSession {
  mathFractions(revision: number) {
    return docxMathFractions(
      this.call({ operation: "docxMathFractions", revision }),
    );
  }
  mathScripts(revision: number) {
    return docxMathScripts(
      this.call({ operation: "docxMathScripts", revision }),
    );
  }
  editMathFraction(
    revision: number,
    fraction: DocxFractionEdit,
    profile: Record<string, string> = {},
  ): EditState {
    checkDocxFractionEdit(fraction);
    return editState(
      this.call({
        operation: "editDocxMathFraction",
        revision,
        fraction,
        profile,
      }),
    );
  }
  editMathScript(
    revision: number,
    script: DocxScriptEdit,
    profile: Record<string, string> = {},
  ): EditState {
    checkDocxScriptEdit(script);
    return editState(
      this.call({ operation: "editDocxMathScript", revision, script, profile }),
    );
  }
}
