import { DocumentError } from "@open-document/wasm/foundation";
import type {
  PptxFindOptions,
  PptxSearchResult,
} from "@open-document/wasm/pptx";
import type { EditorSnapshot } from "./editor-state.js";

export interface PresentationSearchResult extends PptxSearchResult {
  documentId: string;
  slide: string;
  text: string;
  options: PptxFindOptions;
}

export function checkPresentationSearch(
  result: PresentationSearchResult,
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
