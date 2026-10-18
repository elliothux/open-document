import { record, integer } from "./validation.js";
import type { CellRange } from "./xlsx.js";

export interface XlsxCellBorder {
  style: "none" | "thin" | "medium" | "thick";
  color: string;
}
export interface XlsxCellFormat {
  family?: string;
  size?: number;
  bold?: boolean;
  italic?: boolean;
  color?: string;
  fill?: string;
  horizontal?: "general" | "left" | "center" | "right";
  vertical?: "top" | "center" | "bottom";
  wrap?: boolean;
  numberFormat?: string;
  left?: XlsxCellBorder;
  right?: XlsxCellBorder;
  top?: XlsxCellBorder;
  bottom?: XlsxCellBorder;
}
export interface CopiedCellFormat {
  cells: Required<XlsxCellFormat>[][];
  merges: CellRange[];
}

const cellFormatFields = [
  "family",
  "size",
  "bold",
  "italic",
  "color",
  "fill",
  "horizontal",
  "vertical",
  "wrap",
  "numberFormat",
  "left",
  "right",
  "top",
  "bottom",
] as const;

export function copiedCellFormat(value: unknown): CopiedCellFormat {
  const format = record(value),
    cells = format.cells;
  if (
    Object.keys(format).length !== 2 ||
    Object.keys(format).some((key) => !["cells", "merges"].includes(key)) ||
    !Array.isArray(format.merges) ||
    format.merges.length > 1024
  )
    throw new Error("Invalid copied cell format");
  if (
    !Array.isArray(cells) ||
    cells.length === 0 ||
    cells.length > 4096 ||
    !Array.isArray(cells[0]) ||
    cells[0].length === 0 ||
    cells.length * cells[0].length > 4096
  )
    throw new Error("Invalid copied cell format size");
  for (const row of cells) {
    if (!Array.isArray(row) || row.length !== cells[0].length)
      throw new Error("Copied cell format must be rectangular");
    for (const cell of row) {
      checkXlsxCellFormat(cell);
      const fields = record(cell);
      if (!cellFormatFields.every((key) => key in fields))
        throw new Error("Copied cell format requires every property");
    }
  }
  const occupied = new Set<number>();
  for (const value of format.merges) {
    const merge = record(value);
    const { top, left, bottom, right } = merge;
    if (
      Object.keys(merge).length !== 4 ||
      Object.keys(merge).some(
        (key) => !["top", "left", "bottom", "right"].includes(key),
      ) ||
      typeof top !== "number" ||
      typeof left !== "number" ||
      typeof bottom !== "number" ||
      typeof right !== "number" ||
      !integer(top, 1, cells.length) ||
      !integer(bottom, top, cells.length) ||
      !integer(left, 1, cells[0].length) ||
      !integer(right, left, cells[0].length) ||
      (top === bottom && left === right)
    )
      throw new Error("Copied merge must fit the format rectangle");
    for (let row = top; row <= bottom; row++)
      for (let column = left; column <= right; column++) {
        const index = (row - 1) * cells[0].length + column - 1;
        if (occupied.has(index))
          throw new Error("Copied merged ranges overlap");
        occupied.add(index);
      }
  }
  return value as CopiedCellFormat;
}
export type XlsxFormatting = {
  [K in keyof Required<XlsxCellFormat>]: Required<XlsxCellFormat>[K] | null;
} & {
  readOnlyReason: string;
  fontKeys: string[];
};
export const xlsxNumberFormats = [
  "General",
  "@",
  "0",
  "0.00",
  "#,##0",
  "#,##0.00",
  "0%",
  "0.00%",
  "yyyy-mm-dd",
  "mm-dd-yy",
  "d-mmm-yy",
  "d-mmm",
  "mmm-yy",
  "h:mm AM/PM",
  "h:mm:ss AM/PM",
  "h:mm",
  "hh:mm:ss",
  "m/d/yy h:mm",
] as const;

export function checkXlsxCellFormat(value: unknown): void {
  const patch = record(value);
  for (const [key, value] of Object.entries(patch)) {
    let valid = false;
    if (key === "family")
      valid =
        typeof value === "string" &&
        value.length > 0 &&
        value.length <= 256 &&
        value.isWellFormed() &&
        Array.from(value).every(
          (character) =>
            character >= " " && character !== "\u007f" && character !== "|",
        );
    if (key === "size")
      valid =
        typeof value === "number" &&
        Number.isFinite(value) &&
        value >= 1 &&
        value <= 409;
    if (["bold", "italic", "wrap"].includes(key))
      valid = typeof value === "boolean";
    if (["color", "fill"].includes(key))
      valid =
        typeof value === "string" &&
        (/^[0-9a-fA-F]{6}$/u.test(value) || (key === "fill" && value === ""));
    if (key === "horizontal")
      valid =
        typeof value === "string" &&
        ["general", "left", "center", "right"].includes(value);
    if (key === "vertical")
      valid =
        typeof value === "string" &&
        ["top", "center", "bottom"].includes(value);
    if (key === "numberFormat")
      valid =
        typeof value === "string" &&
        xlsxNumberFormats.some((format) => format === value);
    if (["left", "right", "top", "bottom"].includes(key)) {
      const border = record(value);
      valid =
        Object.keys(border).every((field) =>
          ["style", "color"].includes(field),
        ) &&
        typeof border.style === "string" &&
        ["none", "thin", "medium", "thick"].includes(border.style) &&
        typeof border.color === "string" &&
        /^[0-9a-fA-F]{6}$/u.test(border.color);
    }
    if (!valid) throw new Error(`Invalid cell format property: ${key}`);
  }
}

export function xlsxFormatting(value: unknown): XlsxFormatting {
  const fields = record(value);
  const patch = Object.fromEntries(
    Object.entries(fields).filter(
      ([key, value]) =>
        key !== "fontKeys" && key !== "readOnlyReason" && value !== null,
    ),
  );
  checkXlsxCellFormat(patch);
  for (const key of cellFormatFields) {
    if (!(key in fields)) throw new Error("Missing cell format property");
  }
  if (
    typeof fields.readOnlyReason !== "string" ||
    !Array.isArray(fields.fontKeys) ||
    fields.fontKeys.length > 4096 ||
    !fields.fontKeys.every(
      (key) =>
        typeof key === "string" &&
        key.length > 0 &&
        key.length <= 512 &&
        key.isWellFormed(),
    )
  )
    throw new Error("Invalid cell format state");
  return value as XlsxFormatting;
}
