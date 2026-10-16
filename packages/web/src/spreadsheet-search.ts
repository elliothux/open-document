import { DocumentError } from "@open-document/wasm/foundation";
import type {
  XlsxFindOptions,
  XlsxSearchResult,
} from "@open-document/wasm/xlsx";
import type { EditorSnapshot } from "./editor-state.js";

export interface SpreadsheetSearchResult extends XlsxSearchResult {
  documentId: string;
  sheet: string;
  text: string;
  options: XlsxFindOptions;
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
