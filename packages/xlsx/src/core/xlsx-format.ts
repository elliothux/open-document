import { record, integer } from "@open-document/wasm/abi/validation";
import type { CellRange } from "./xlsx.js";

export const xlsxBorderStyles = [
  "none",
  "thin",
  "medium",
  "thick",
  "double",
  "hair",
  "dotted",
  "dashed",
  "dashDot",
  "dashDotDot",
  "mediumDashed",
  "mediumDashDot",
  "mediumDashDotDot",
  "slantDashDot",
] as const;
export interface XlsxCellBorder {
  style: (typeof xlsxBorderStyles)[number];
  color: string;
}
export interface XlsxCellFormat {
  family?: string;
  size?: number;
  bold?: boolean;
  italic?: boolean;
  underline?: boolean;
  strike?: boolean;
  script?: "baseline" | "superscript" | "subscript";
  color?: string;
  fill?: string;
  horizontal?:
    | "general"
    | "left"
    | "center"
    | "right"
    | "justify"
    | "centerContinuous"
    | "distributed"
    | "fill";
  vertical?: "top" | "center" | "bottom" | "justify" | "distributed";
  wrap?: boolean;
  shrinkToFit?: boolean;
  indent?: number;
  /** OOXML: 0–90 counterclockwise, 91–180 clockwise, 255 stacked. */
  textRotation?: number;
  /** Input protection takes effect when worksheet protection is enabled. */
  locked?: boolean;
  /** Conceals formula source while worksheet protection is enabled. */
  formulaHidden?: boolean;
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
  "underline",
  "strike",
  "script",
  "color",
  "fill",
  "horizontal",
  "vertical",
  "wrap",
  "shrinkToFit",
  "indent",
  "textRotation",
  "locked",
  "formulaHidden",
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
  "0.00E+00",
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
  "0.0",
  "0.000",
  "0.0000",
  "#,##0.0",
  "#,##0.000",
  "#,##0.0000",
  "0.0%",
  "0.000%",
  "0.0000%",
  "$0.00",
  "$#,##0.00",
  "¥0.00",
  "¥#,##0.00",
] as const;

function numberFormatSource(value: string): boolean {
  return (
    value.length > 0 &&
    value.length <= 256 &&
    value.isWellFormed() &&
    !Array.from(value).some(
      (c) => c < " " || ["\u007f", "\u2028", "\u2029"].includes(c),
    )
  );
}

function integerNumberFormat(value: string): boolean {
  if (!numberFormatSource(value)) return false;
  const tokens = value.match(/0|\\[\s\S]|"[^"]*"|,+/gu);
  if (tokens === null || tokens.join("") !== value || !tokens.includes("0"))
    return false;
  const comma = tokens.findIndex((token) => token.startsWith(","));
  return (
    comma < 0 || (comma === tokens.length - 1 && tokens[comma - 1] === "0")
  );
}

function dateNumberFormat(value: string): boolean {
  if (!numberFormatSource(value)) return false;
  const locale = /^\[\$-([0-9a-f]{1,4})\]/iu.exec(value);
  if (locale) {
    const id = Number.parseInt(locale[1]!, 16);
    if (id === 0xf800 || ((id & 0x3ff) !== 9 && id < 0xf000)) return false;
    value = value.slice(locale[0].length);
  }
  const tokens = value.match(
    /AM\/PM|(?:yyyy|yy)(?!y)|m{1,4}(?!m)|d{1,2}(?!d)|h{1,2}(?!h)|s{1,2}(?!s)(?:\.000)?|"[^"]*"|\\[\s\S]|[ /:,.-]/giu,
  );
  return (
    tokens !== null &&
    tokens.join("") === value &&
    tokens.some((token) => /^[ymdhs]|^AM\/PM$/iu.test(token))
  );
}

function sectionNumberFormat(value: string): boolean {
  if (!numberFormatSource(value)) return false;
  const tokens = value.match(
    /\\[\s\S]|"[^"]*"|[_*][\s\S]|\[[a-z]+\]|[#0?][#0?,.]*|@|[ ;+()$¥%-]/giu,
  );
  if (tokens === null || tokens.join("") !== value) return false;
  let sections = 1,
    position = 0,
    numeric = false,
    text = false,
    percent = false;
  for (const token of tokens) {
    if (token === ";") {
      if (++sections > 4) return false;
      position = 0;
      numeric = false;
      text = false;
      percent = false;
      continue;
    }
    if (token.startsWith("[")) {
      if (
        position !== 0 ||
        ![
          "black",
          "blue",
          "cyan",
          "green",
          "magenta",
          "red",
          "white",
          "yellow",
        ].includes(token.slice(1, -1).toLowerCase())
      )
        return false;
    } else if (token === "@") {
      if (numeric || text || percent) return false;
      text = true;
    } else if (token === "%") {
      if (text) return false;
      percent = true;
    } else if (/^[#0?]/u.test(token)) {
      if (numeric || text) return false;
      const mask = /^([#?0]+(?:,[#?0]+)*)(?:\.(0{1,30}))?$/u.exec(token);
      if (!mask || !/^[#?]*0*$/u.test(mask[1]!.replaceAll(",", "")))
        return false;
      numeric = true;
    }
    position++;
  }
  return true;
}

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
    if (key === "indent") valid = integer(value, 0, 250);
    if (key === "textRotation") valid = integer(value, 0, 180) || value === 255;
    if (
      [
        "bold",
        "italic",
        "underline",
        "strike",
        "wrap",
        "shrinkToFit",
        "locked",
        "formulaHidden",
      ].includes(key)
    )
      valid = typeof value === "boolean";
    if (["color", "fill"].includes(key))
      valid =
        typeof value === "string" &&
        (/^[0-9a-fA-F]{6}$/u.test(value) || (key === "fill" && value === ""));
    if (key === "horizontal")
      valid =
        typeof value === "string" &&
        [
          "general",
          "left",
          "center",
          "right",
          "justify",
          "centerContinuous",
          "distributed",
          "fill",
        ].includes(value);
    if (key === "script")
      valid =
        typeof value === "string" &&
        ["baseline", "superscript", "subscript"].includes(value);
    if (key === "vertical")
      valid =
        typeof value === "string" &&
        ["top", "center", "bottom", "justify", "distributed"].includes(value);
    if (key === "numberFormat")
      valid =
        typeof value === "string" &&
        (xlsxNumberFormats.some((format) => format === value) ||
          (/^0(?:\.0{1,30})?E[+-]0{1,6}$/iu.test(value) &&
            value === value.trim()) ||
          dateNumberFormat(value) ||
          integerNumberFormat(value) ||
          sectionNumberFormat(value));
    if (["left", "right", "top", "bottom"].includes(key)) {
      const border = record(value);
      valid =
        Object.keys(border).every((field) =>
          ["style", "color"].includes(field),
        ) &&
        typeof border.style === "string" &&
        xlsxBorderStyles.some((style) => style === border.style) &&
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
