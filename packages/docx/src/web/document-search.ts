import type { DocumentHost } from "./document-host.js";
import type { FoundationClient } from "./foundation.js";
import type { DocxFindOptions } from "../core/foundation.js";
import {
  searchSelections,
  type DocumentSearchResult,
} from "./document-selection.js";
export function createDocumentSearch(
  client: FoundationClient,
  host: DocumentHost & { endGroup(): void },
) {
  return {
    find(
      text: string,
      options: DocxFindOptions = {},
    ): Promise<DocumentSearchResult> {
      host.endGroup();
      return host.read(async () => ({
        ...(await client.execute({
          operation: "findDocx",
          revision: host.snapshot().revision,
          text: text,
          options: options,
        })),
        documentId: host.snapshot().documentId,
      }));
    },
    selectMatch(result: DocumentSearchResult, index: number): Promise<void> {
      return host.edit(() =>
        client.execute({
          operation: "selectDocx",
          revision: result.revision,
          selection: searchSelections(result, host.snapshot(), index)[0]!,
        }),
      );
    },
    replaceMatches(
      result: DocumentSearchResult,
      text: string,
      index?: number,
    ): Promise<void> {
      return host.edit(() =>
        client.execute({
          operation: "replaceDocxMatches",
          revision: result.revision,
          matches: searchSelections(result, host.snapshot(), index),
          text: text,
        }),
      );
    },
  };
}
