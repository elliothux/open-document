import { record, integer } from "./validation.js";

export interface DocxFractionValue {
  numerator: string;
  denominator: string;
}
export type DocxFractionEdit =
  | (DocxFractionValue & { action: "insert" })
  | (DocxFractionValue & { action: "update"; id: number })
  | { action: "delete"; id: number };
export interface DocxMathFractions {
  revision: number;
  items: (DocxFractionValue & { id: number; reason: string })[];
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
export function checkDocxFractionEdit(value: unknown): void {
  const edit = record(value);
  const insert = edit.action === "insert",
    remove = edit.action === "delete";
  const keys = remove
    ? ["action", "id"]
    : insert
      ? ["action", "numerator", "denominator"]
      : ["action", "id", "numerator", "denominator"];
  if (
    typeof edit.action !== "string" ||
    !["insert", "update", "delete"].includes(edit.action) ||
    Object.keys(edit).length !== keys.length ||
    Object.keys(edit).some((key) => !keys.includes(key)) ||
    (!insert && !integer(edit.id, 0, 2147483647)) ||
    (!remove &&
      (!fractionText(edit.numerator) ||
        !fractionText(edit.denominator) ||
        edit.numerator.length + edit.denominator.length > 4096))
  )
    throw new Error("Invalid fraction edit");
}
export function docxMathFractions(value: unknown): DocxMathFractions {
  const catalog = record(value);
  if (
    Object.keys(catalog).length !== 2 ||
    !integer(catalog.revision, 0, 2147483647) ||
    !Array.isArray(catalog.items) ||
    catalog.items.length > 256
  )
    throw new Error("Invalid fraction catalog");
  const ids = new Set<number>();
  for (const item of catalog.items) {
    const fraction = record(item);
    if (
      Object.keys(fraction).length !== 4 ||
      typeof fraction.id !== "number" ||
      !integer(fraction.id, 0, 2147483647) ||
      typeof fraction.reason !== "string" ||
      typeof fraction.numerator !== "string" ||
      typeof fraction.denominator !== "string" ||
      fraction.numerator.length + fraction.denominator.length > 4096 ||
      ![fraction.numerator, fraction.denominator, fraction.reason].every(
        (text) => text.isWellFormed(),
      ) ||
      ids.has(fraction.id)
    )
      throw new Error("Invalid fraction catalog item");
    if (!fraction.reason)
      checkDocxFractionEdit({
        action: "update",
        id: fraction.id,
        numerator: fraction.numerator,
        denominator: fraction.denominator,
      });
    ids.add(fraction.id);
  }
  return value as DocxMathFractions;
}
