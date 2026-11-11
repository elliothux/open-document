import { record } from "@open-document/wasm/abi/validation";

export interface XlsxFindOptions {
  matchCase?: boolean;
  wholeCell?: boolean;
  /** Search editable formula source rather than calculated results. Defaults to true. */
  formulas?: boolean;
  workbook?: boolean;
}
export interface XlsxSearchResult {
  revision: number;
  truncated: boolean;
  matches: {
    sheet: string;
    name: string;
    address: string;
    hidden: boolean;
    snippet: string;
    reason: string;
  }[];
}

export function xlsxFindOptions(
  options: XlsxFindOptions,
): Required<XlsxFindOptions> {
  const values = record(options);
  if (
    !options ||
    typeof options !== "object" ||
    Array.isArray(options) ||
    !Object.entries(values).every(
      ([key, value]) =>
        ["matchCase", "wholeCell", "formulas", "workbook"].includes(key) &&
        (value === undefined || typeof value === "boolean"),
    )
  )
    throw new Error("Invalid literal cell search options");
  return {
    matchCase: options.matchCase ?? false,
    wholeCell: options.wholeCell ?? false,
    formulas: options.formulas ?? true,
    workbook: options.workbook ?? false,
  };
}
