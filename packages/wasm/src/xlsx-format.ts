import { record } from "./validation.js";

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
  for (const key of [
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
  ]) {
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
