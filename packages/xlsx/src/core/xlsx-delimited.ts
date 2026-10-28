import { integer, record } from "@open-document/wasm/abi/validation";
import { xlsxBounds } from "./xlsx-geometry.js";

export interface XlsxDelimitedOptions {
  numbers?: boolean;
  dates?: boolean;
  formulas?: boolean;
}

export function xlsxDelimitedOptions(
  options: XlsxDelimitedOptions,
): Required<XlsxDelimitedOptions> {
  const values = record(options);
  if (
    !options ||
    typeof options !== "object" ||
    Array.isArray(options) ||
    !Object.entries(values).every(
      ([key, value]) =>
        ["numbers", "dates", "formulas"].includes(key) &&
        (value === undefined || typeof value === "boolean"),
    )
  )
    throw new Error("Invalid delimited import options");
  return {
    numbers: options.numbers ?? false,
    dates: options.dates ?? false,
    formulas: options.formulas ?? false,
  };
}

export type XlsxTextColumnType =
  "text" | "general" | "ymd" | "mdy" | "dmy" | "skip";
export type XlsxTextColumnSettings = {
  range: string;
  types?: XlsxTextColumnType[];
  formulas?: boolean;
} & ({ delimiter: "," | ";" | " " | "\t" } | { breaks: number[] });
export type XlsxTextColumns = XlsxTextColumnSettings & {
  revision: number;
  sheet: string;
  resultRange: string;
  columns: number;
  overwrittenCells: number;
  splitColumns: number;
  types: XlsxTextColumnType[];
  formulas: boolean;
  /** First ten output rows, padded to the output width. */
  preview: string[][];
};
export function checkXlsxTextColumnSettings(value: unknown): void {
  const settings = record(value),
    source = xlsxBounds(settings.range);
  if (
    Object.keys(settings).length < 2 ||
    Object.keys(settings).length > 4 ||
    Object.keys(settings).some(
      (key) =>
        !["range", "delimiter", "breaks", "types", "formulas"].includes(key),
    ) ||
    source.left !== source.right ||
    "delimiter" in settings === "breaks" in settings ||
    (settings.formulas !== undefined &&
      typeof settings.formulas !== "boolean") ||
    (settings.types !== undefined &&
      (!Array.isArray(settings.types) ||
        settings.types.length > 4096 ||
        settings.types.some(
          (kind) =>
            typeof kind !== "string" ||
            !["text", "general", "ymd", "mdy", "dmy", "skip"].includes(kind),
        )))
  )
    throw new Error("Invalid text to columns settings");
  if ("breaks" in settings) {
    if (
      !Array.isArray(settings.breaks) ||
      !settings.breaks.length ||
      settings.breaks.length > 4095
    )
      throw new Error("Invalid fixed-width positions");
    let previous = 0;
    for (const position of settings.breaks) {
      if (!integer(position, previous + 1, 65534))
        throw new Error("Fixed-width positions must be increasing");
      previous = Number(position);
    }
  } else if (
    typeof settings.delimiter !== "string" ||
    ![",", ";", " ", "\t"].includes(settings.delimiter)
  )
    throw new Error("Invalid text delimiter");
}
export function xlsxTextColumns(value: unknown): XlsxTextColumns {
  const result = record(value);
  if ("delimiter" in result === "breaks" in result)
    throw new Error("Ambiguous text split mode");
  checkXlsxTextColumnSettings(
    "breaks" in result
      ? {
          range: result.range,
          breaks: result.breaks,
          types: result.types,
          formulas: result.formulas,
        }
      : {
          range: result.range,
          delimiter: result.delimiter,
          types: result.types,
          formulas: result.formulas,
        },
  );
  const source = xlsxBounds(result.range),
    target = xlsxBounds(result.resultRange),
    height = source.bottom - source.top + 1,
    width = target.right - target.left + 1;
  if (
    !integer(result.revision, 0, 2147483647) ||
    typeof result.sheet !== "string" ||
    !result.sheet ||
    result.sheet.length > 65535 ||
    target.top !== source.top ||
    target.bottom !== source.bottom ||
    target.left !== source.left ||
    result.columns !== width ||
    !integer(result.splitColumns, width, 4096) ||
    Number(result.splitColumns) * height > 4096 ||
    !Array.isArray(result.types) ||
    result.types.length !== result.splitColumns ||
    result.types.filter((kind) => kind !== "skip").length !== width ||
    typeof result.formulas !== "boolean" ||
    (Array.isArray(result.breaks) &&
      result.breaks.length + 1 !== result.splitColumns) ||
    !integer(result.overwrittenCells, 0, height * (width - 1)) ||
    !Array.isArray(result.preview) ||
    result.preview.length !== Math.min(10, height)
  )
    throw new Error("Invalid text to columns preview");
  let units = 0;
  for (const row of result.preview) {
    if (!Array.isArray(row) || row.length !== width)
      throw new Error("Invalid text to columns preview width");
    for (const text of row) {
      if (
        typeof text !== "string" ||
        !text.isWellFormed() ||
        text.length > 32767
      )
        throw new Error("Invalid split text");
      units += text.length;
      if (units > 1048576) throw new Error("Split preview exceeds text budget");
    }
  }
  return value as XlsxTextColumns;
}
