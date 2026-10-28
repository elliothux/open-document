import { record } from "@open-document/wasm/abi/validation";
import type { DocxSelection } from "./foundation.js";

export interface DocxFindOptions {
  matchCase?: boolean;
  wholeWord?: boolean;
}
export interface DocxSearchResult {
  revision: number;
  truncated: boolean;
  matches: { selection: DocxSelection; snippet: string; reason: string }[];
}

export function isDocxSelection(value: unknown): value is DocxSelection {
  const integer = (value: unknown): boolean =>
    typeof value === "number" &&
    Number.isSafeInteger(value) &&
    value >= 0 &&
    value <= 2147483647;
  const position = (value: unknown): boolean => {
    const object = record(value);
    return (
      integer(object.paragraph) &&
      integer(object.offset) &&
      (object.bidiLevel === undefined ||
        (integer(object.bidiLevel) && Number(object.bidiLevel) <= 126)) &&
      (object.frameStart === undefined ||
        (integer(object.frameStart) &&
          Number(object.frameStart) > Number(object.offset))) &&
      (object.affinity === "before" || object.affinity === "after")
    );
  };
  const object = record(value);
  return position(object.anchor) && position(object.focus);
}

export function checkFindOptions(options: DocxFindOptions): void {
  const values = record(options);
  if (
    options === null ||
    typeof options !== "object" ||
    Array.isArray(options) ||
    !Object.entries(values).every(
      ([key, value]) =>
        ["matchCase", "wholeWord"].includes(key) &&
        (value === undefined || typeof value === "boolean"),
    )
  )
    throw new Error("Invalid literal search options");
}

export function docxSearchResult(value: unknown): DocxSearchResult {
  const object = record(value);
  if (
    !Number.isSafeInteger(object.revision) ||
    Number(object.revision) < 0 ||
    typeof object.truncated !== "boolean" ||
    !Array.isArray(object.matches) ||
    object.matches.length > 1000 ||
    !object.matches.every((value: unknown) => {
      const item = record(value);
      return (
        isDocxSelection(item.selection) &&
        typeof item.snippet === "string" &&
        item.snippet.length <= 80 &&
        typeof item.reason === "string"
      );
    })
  )
    throw new Error("Invalid DOCX search result returned by Wasm");
  return value as DocxSearchResult;
}
