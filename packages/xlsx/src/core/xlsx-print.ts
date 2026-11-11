import { record } from "@open-document/wasm/abi/validation";
import {
  xlsxHeaderFooterTextUnits,
  xlsxPrintAreaUnits,
  xlsxPrintFitPageCount,
  xlsxPrintPageMaxPoints,
  xlsxPrintPaperMinPoints,
  xlsxPrintScaleMax,
  xlsxPrintScaleMin,
  xlsxPrintSheetLimit,
  xlsxPrintTitleUnits,
} from "@open-document/wasm/engine-source";

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
  /** Up to 32 comma-separated cell rectangles, replacing the saved print areas. */
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
  /** Up to 32 comma-separated cell rectangles; an empty string clears the areas. */
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
      (key) =>
        typeof settings[key] === "string" &&
        settings[key].length <= xlsxHeaderFooterTextUnits,
    ) ||
    ![
      "differentFirst",
      "differentOddEven",
      "scaleWithDoc",
      "alignWithMargins",
    ].every((key) => typeof settings[key] === "boolean") ||
    !["headerMargin", "footerMargin"].every((key) =>
      finite(settings[key], 0, xlsxPrintPageMaxPoints),
    )
  )
    throw new Error("Invalid worksheet header/footer");
}
export function checkXlsxPrintRange(value: unknown): void {
  const range = record(value);
  if (
    !(["area", "rows", "columns"] as const).every(
      (key) =>
        typeof range[key] === "string" &&
        range[key].length <=
          (key === "area" ? xlsxPrintAreaUnits : xlsxPrintTitleUnits),
    )
  )
    throw new Error("Invalid worksheet print range");
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
      finite(setup[key], 0, xlsxPrintPageMaxPoints),
    ) ||
    !finite(setup.scale, xlsxPrintScaleMin, xlsxPrintScaleMax) ||
    !Number.isInteger(setup.scale) ||
    ![setup.fitWidth, setup.fitHeight].every(
      (value) =>
        finite(value, 0, xlsxPrintFitPageCount) && Number.isInteger(value),
    )
  )
    throw new Error("Invalid worksheet print setup");
}
export function checkPrintOptions(value: unknown): void {
  if (value === null) return;
  const options = record(value);
  const paper = ["width", "height", "left", "top", "right", "bottom"];
  const hasPaper = paper.some((key) => options[key] !== undefined);
  if (
    (hasPaper &&
      (!finite(
        options.width,
        xlsxPrintPaperMinPoints,
        xlsxPrintPageMaxPoints,
      ) ||
        !finite(
          options.height,
          xlsxPrintPaperMinPoints,
          xlsxPrintPageMaxPoints,
        ) ||
        !["left", "top", "right", "bottom"].every((key) =>
          finite(options[key], 0, xlsxPrintPageMaxPoints),
        ))) ||
    (options.range !== undefined &&
      (typeof options.range !== "string" ||
        options.range.length === 0 ||
        options.range.length > xlsxPrintAreaUnits)) ||
    (options.sheets !== undefined &&
      options.sheets !== "visible" &&
      (!Array.isArray(options.sheets) ||
        options.sheets.length === 0 ||
        options.sheets.length > xlsxPrintSheetLimit ||
        !options.sheets.every(
          (id) => typeof id === "string" && id.length > 0 && id.length <= 4096,
        ) ||
        new Set(options.sheets).size !== options.sheets.length))
  )
    throw new Error("Invalid worksheet print options");
}
