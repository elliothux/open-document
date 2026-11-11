import type { SpreadsheetHost } from "./spreadsheet-host.js";
import { DocumentError } from "@open-document/wasm/abi/session";
import type { XlsxFindOptions, XlsxSearchResult } from "../core/xlsx.js";
import { xlsxFindOptions } from "../core/xlsx.js";
import type { EditorSnapshot } from "@open-document/web-core/editor-state";
import type { XlsxClient } from "./xlsx.js";

export interface SpreadsheetSearchResult extends XlsxSearchResult {
  documentId: string;
  sheet: string;
  text: string;
  options: XlsxFindOptions;
}

/** Search reads the host's current state and uses its draft and edit barriers. */
export function createSpreadsheetSearch(
  client: XlsxClient,
  host: SpreadsheetHost & {
    snapshot(): EditorSnapshot;
  },
) {
  return {
    find(text: string, options: XlsxFindOptions = {}) {
      return host.read(() => {
        const { revision, sheet } = host.state();
        return findSpreadsheet(
          client,
          revision,
          sheet,
          text,
          options,
          host.snapshot().documentId,
        );
      });
    },
    selectMatch(result: SpreadsheetSearchResult, index: number) {
      return host.change(() =>
        selectSpreadsheetMatch(client, result, host.snapshot(), index),
      );
    },
    replaceMatches(
      result: SpreadsheetSearchResult,
      replacement: string,
      index?: number,
    ) {
      return host.change(() =>
        replaceSpreadsheetMatches(
          client,
          result,
          host.snapshot(),
          replacement,
          index,
        ),
      );
    },
  };
}

export function replaceSpreadsheetMatches(
  client: XlsxClient,
  result: SpreadsheetSearchResult,
  snapshot: EditorSnapshot,
  replacement: string,
  index?: number,
) {
  checkSpreadsheetSearch(result, snapshot, index);
  return client.execute({
    operation: "replaceXlsxMatches",
    revision: result.revision,
    sheet: result.sheet,
    text: result.text,
    options: result.options,
    replacement: replacement,
    index: index,
  });
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
    ...(await client.execute({
      operation: "findXlsx",
      revision: revision,
      sheet: sheet,
      text: text,
      options: options,
    })),
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
  return client.execute({
    operation: "selectXlsx",
    revision: result.revision,
    sheet: match.sheet,
    range: match.address,
  });
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
