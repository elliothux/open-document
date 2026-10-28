import { integer, record } from "@open-document/wasm/abi/validation";
import type { MathFormat } from "@open-document/wasm/abi/math";
export type { MathFormat } from "@open-document/wasm/abi/math";

export interface PptxMathTarget {
  object: string;
  revision: number;
  node: number;
}
export interface PptxMathValue {
  latex: string;
  format: MathFormat;
}
export interface PptxMathItem extends PptxMathValue {
  node: number;
  reason: string;
}
export type PptxMathEdit =
  | (PptxMathValue & {
      action: "insertMath";
      x: number;
      y: number;
      width: number;
      height: number;
    })
  | (PptxMathValue & { action: "appendMath"; position: "start" | "end" })
  | (PptxMathValue & { action: "updateMath"; target: PptxMathTarget })
  | { action: "deleteMath"; target: PptxMathTarget };

function text(value: unknown, limit: number): value is string {
  return (
    typeof value === "string" &&
    !!value.trim() &&
    value.length <= limit &&
    value.isWellFormed() &&
    Array.from(value).every(
      (c) =>
        c.codePointAt(0)! >= 32 &&
        !["\u2028", "\u2029", "\ufffe", "\uffff"].includes(c),
    )
  );
}
function mathValue(value: Record<string, unknown>): void {
  const format = record(value.format);
  if (
    !text(value.latex, 131072) ||
    Object.keys(format).length !== 3 ||
    !text(format.family, 255) ||
    typeof format.size !== "number" ||
    !Number.isFinite(format.size) ||
    format.size < 0.5 ||
    format.size > 409 ||
    Math.abs(format.size * 100 - Math.round(format.size * 100)) > 0.000001 ||
    typeof format.color !== "string" ||
    !/^[a-fA-F0-9]{6}$/.test(format.color)
  )
    throw new Error("Invalid equation value");
}
export function checkPptxMathEdit(value: unknown): boolean {
  const edit = record(value);
  if (
    !["insertMath", "appendMath", "updateMath", "deleteMath"].some(
      (action) => edit.action === action,
    )
  )
    return false;
  const keys =
    edit.action === "insertMath"
      ? ["action", "latex", "format", "x", "y", "width", "height"]
      : edit.action === "appendMath"
        ? ["action", "latex", "format", "position"]
        : edit.action === "updateMath"
          ? ["action", "latex", "format", "target"]
          : ["action", "target"];
  if (
    Object.keys(edit).length !== keys.length ||
    Object.keys(edit).some((key) => !keys.includes(key))
  )
    throw new Error("Invalid equation edit fields");
  if (edit.action !== "deleteMath") mathValue(edit);
  if (
    edit.action === "appendMath" &&
    edit.position !== "start" &&
    edit.position !== "end"
  )
    throw new Error("Invalid equation insertion position");
  if (edit.action === "updateMath" || edit.action === "deleteMath") {
    const target = record(edit.target);
    if (
      Object.keys(target).length !== 3 ||
      !text(target.object, 4096) ||
      !integer(target.node, 0, 2147483647) ||
      !integer(target.revision, 0, 2147483647)
    )
      throw new Error("Invalid equation target");
  }
  if (edit.action === "insertMath")
    for (const key of ["x", "y", "width", "height"]) {
      const number = edit[key];
      if (
        typeof number !== "number" ||
        !Number.isFinite(number) ||
        Math.abs(number) > 14400 ||
        ((key === "width" || key === "height") && number < 0.1)
      )
        throw new Error("Invalid equation frame");
    }
  return true;
}
export function checkPptxMathItems(value: unknown): void {
  if (!Array.isArray(value) || value.length > 65536)
    throw new Error("Invalid equation catalog");
  const ids = new Set<number>();
  for (const entry of value) {
    const item = record(entry);
    mathValue(item);
    if (
      Object.keys(item).length !== 4 ||
      typeof item.node !== "number" ||
      !integer(item.node, 0, 2147483647) ||
      ids.has(item.node) ||
      typeof item.reason !== "string" ||
      !item.reason.isWellFormed()
    )
      throw new Error("Invalid equation catalog item");
    ids.add(item.node);
  }
}
