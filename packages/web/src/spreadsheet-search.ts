import { DocumentError } from "@open-document/wasm/foundation";
import type {
  XlsxFindOptions,
  XlsxSearchResult,
} from "@open-document/wasm/xlsx";
import { xlsxFindOptions } from "@open-document/wasm/xlsx";
import type { EditorSnapshot } from "./editor-state.js";
import type { XlsxClient } from "./xlsx.js";

export interface SpreadsheetSearchResult extends XlsxSearchResult {
  documentId: string;
  sheet: string;
  text: string;
  options: XlsxFindOptions;
}

export function replaceSpreadsheetMatches(
  client: XlsxClient,
  result: SpreadsheetSearchResult,
  snapshot: EditorSnapshot,
  replacement: string,
  index?: number,
) {
  checkSpreadsheetSearch(result, snapshot, index);
  return client.replaceMatches(
    result.revision,
    result.sheet,
    result.text,
    result.options,
    replacement,
    index,
  );
}

export async function findSpreadsheet(
  client: XlsxClient,
  revision: number,
  sheet: string,
  text: string,
  options: XlsxFindOptions,
  documentId: string,
): Promise<SpreadsheetSearchResult> {
  options = xlsxFindOptions(options);
  return {
    ...(await client.find(revision, sheet, text, options)),
    documentId,
    sheet,
    text,
    options,
  };
}

export function selectSpreadsheetMatch(
  client: XlsxClient,
  result: SpreadsheetSearchResult,
  snapshot: EditorSnapshot,
  index: number,
) {
  checkSpreadsheetSearch(result, snapshot, index);
  const match = result.matches[index]!;
  if (match.hidden)
    throw new Error("Show the worksheet before selecting this match");
  return client.select(result.revision, match.sheet, match.address);
}

export function checkSpreadsheetSearch(
  result: SpreadsheetSearchResult,
  snapshot: EditorSnapshot,
  index?: number,
): void {
  if (
    result.documentId !== snapshot.documentId ||
    result.revision !== snapshot.revision
  )
    throw new DocumentError(
      "stale-search",
      "Document changed; find again before using this result",
      "",
      -1,
    );
  if (
    index !== undefined &&
    (!Number.isInteger(index) || !result.matches[index])
  )
    throw new Error("Search match is missing");
}
