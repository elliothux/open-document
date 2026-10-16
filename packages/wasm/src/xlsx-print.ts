import { record } from "./validation.js";

interface PrintPaper {
  width: number;
  height: number;
  top: number;
  right: number;
  bottom: number;
  left: number;
}
/** Select visible sheets and optionally override all six paper fields together. */
export type PrintOptions = {
  range?: string;
  sheets?: "visible" | readonly string[];
} & (PrintPaper | { [K in keyof PrintPaper]?: never });
export interface XlsxPrintSetup {
  paper: "A4" | "Letter";
  orientation: "portrait" | "landscape";
  left: number;
  top: number;
  right: number;
  bottom: number;
  scale: number;
  fitWidth: number;
  fitHeight: number;
}
export interface XlsxPrintRange {
  area: string;
  rows: string;
  columns: string;
}
export interface XlsxHeaderFooter {
  oddHeader: string;
  oddFooter: string;
  evenHeader: string;
  evenFooter: string;
  firstHeader: string;
  firstFooter: string;
  differentFirst: boolean;
  differentOddEven: boolean;
  scaleWithDoc: boolean;
  alignWithMargins: boolean;
  headerMargin: number;
  footerMargin: number;
}
export function checkXlsxHeaderFooter(value: unknown): void {
  const settings = record(value);
  if (
    ![
      "oddHeader",
      "oddFooter",
      "evenHeader",
      "evenFooter",
      "firstHeader",
      "firstFooter",
    ].every(
      (key) => typeof settings[key] === "string" && settings[key].length <= 255,
    ) ||
    ![
      "differentFirst",
      "differentOddEven",
      "scaleWithDoc",
      "alignWithMargins",
    ].every((key) => typeof settings[key] === "boolean") ||
    !["headerMargin", "footerMargin"].every((key) =>
      finite(settings[key], 0, 14400),
    )
  )
    throw new Error("Invalid worksheet header/footer");
}
export function xlsxHeaderFooter(
  value: unknown,
): XlsxHeaderFooter & { readOnlyReason: string } {
  checkXlsxHeaderFooter(value);
  if (typeof record(value).readOnlyReason !== "string")
    throw new Error("Invalid header/footer protection query");
  return value as XlsxHeaderFooter & { readOnlyReason: string };
}
export function checkXlsxPrintRange(value: unknown): void {
  const range = record(value);
  if (
    !(["area", "rows", "columns"] as const).every(
      (key) =>
        typeof range[key] === "string" &&
        range[key].length <= (key === "area" ? 64 : 32),
    )
  )
    throw new Error("Invalid worksheet print range");
}
export function xlsxPrintRange(
  value: unknown,
): XlsxPrintRange & { readOnlyReason: string } {
  checkXlsxPrintRange(value);
  if (typeof record(value).readOnlyReason !== "string")
    throw new Error("Invalid print range protection query");
  return value as XlsxPrintRange & { readOnlyReason: string };
}
function finite(value: unknown, low: number, high: number): value is number {
  return (
    typeof value === "number" &&
    Number.isFinite(value) &&
    value >= low &&
    value <= high
  );
}
export function checkXlsxPrintSetup(value: unknown): void {
  const setup = record(value);
  if (
    !["A4", "Letter"].includes(String(setup.paper)) ||
    !["portrait", "landscape"].includes(String(setup.orientation)) ||
    !["left", "top", "right", "bottom"].every((key) =>
      finite(setup[key], 0, 14400),
    ) ||
    !finite(setup.scale, 10, 400) ||
    !Number.isInteger(setup.scale) ||
    ![setup.fitWidth, setup.fitHeight].every(
      (value) => finite(value, 0, 1024) && Number.isInteger(value),
    )
  )
    throw new Error("Invalid worksheet print setup");
}
export function xlsxPrintSetup(
  value: unknown,
): XlsxPrintSetup & { readOnlyReason: string } {
  checkXlsxPrintSetup(value);
  if (typeof record(value).readOnlyReason !== "string")
    throw new Error("Invalid print protection query");
  return value as XlsxPrintSetup & { readOnlyReason: string };
}
export function checkPrintOptions(value: unknown): void {
  if (value === null) return;
  const options = record(value);
  const paper = ["width", "height", "left", "top", "right", "bottom"];
  const hasPaper = paper.some((key) => options[key] !== undefined);
  if (
    (hasPaper &&
      (!finite(options.width, 36, 14400) ||
        !finite(options.height, 36, 14400) ||
        !["left", "top", "right", "bottom"].every((key) =>
          finite(options[key], 0, 14400),
        ))) ||
    (options.range !== undefined &&
      (typeof options.range !== "string" ||
        options.range.length === 0 ||
        options.range.length > 64)) ||
    (options.sheets !== undefined &&
      options.sheets !== "visible" &&
      (!Array.isArray(options.sheets) ||
        options.sheets.length === 0 ||
        options.sheets.length > 256 ||
        !options.sheets.every(
          (id) => typeof id === "string" && id.length > 0 && id.length <= 4096,
        ) ||
        new Set(options.sheets).size !== options.sheets.length))
  )
    throw new Error("Invalid worksheet print options");
}
