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

export function xlsxSearchResult(value: unknown): XlsxSearchResult {
  const result = record(value);
  if (
    !Number.isSafeInteger(result.revision) ||
    Number(result.revision) < 0 ||
    Number(result.revision) > 2147483647 ||
    typeof result.truncated !== "boolean" ||
    !Array.isArray(result.matches) ||
    result.matches.length > 4096 ||
    !result.matches.every((value: unknown) => {
      const item = record(value);
      return (
        typeof item.sheet === "string" &&
        item.sheet.length <= 4096 &&
        typeof item.name === "string" &&
        item.name.length <= 31 &&
        typeof item.address === "string" &&
        /^[A-Z]{1,3}[1-9][0-9]{0,6}$/.test(item.address) &&
        typeof item.hidden === "boolean" &&
        typeof item.snippet === "string" &&
        item.snippet.length <= 160 &&
        typeof item.reason === "string"
      );
    })
  )
    throw new Error("Invalid XLSX search result returned by Wasm");
  return value as XlsxSearchResult;
}
