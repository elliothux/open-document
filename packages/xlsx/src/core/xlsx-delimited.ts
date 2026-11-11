import { integer, record } from "@open-document/wasm/abi/validation";
import {
  xlsxTextColumnBreakPosition,
  xlsxTextColumnCells,
} from "@open-document/wasm/engine-source";
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
        settings.types.length > xlsxTextColumnCells ||
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
      settings.breaks.length >= xlsxTextColumnCells
    )
      throw new Error("Invalid fixed-width positions");
    let previous = 0;
    for (const position of settings.breaks) {
      if (!integer(position, previous + 1, xlsxTextColumnBreakPosition))
        throw new Error("Fixed-width positions must be increasing");
      previous = Number(position);
    }
  } else if (
    typeof settings.delimiter !== "string" ||
    ![",", ";", " ", "\t"].includes(settings.delimiter)
  )
    throw new Error("Invalid text delimiter");
}
