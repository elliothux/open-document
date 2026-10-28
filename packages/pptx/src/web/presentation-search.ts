import { DocumentError } from "@open-document/wasm/abi/session";
import {
  pptxFindOptions,
  type PptxFindOptions,
  type PptxSearchResult,
  type PptxQuery,
} from "../core/pptx.js";
import type { EditorSnapshot } from "@open-document/web-core/editor-state";
import type { PptxClient } from "./pptx.js";

export interface PresentationSearchResult extends PptxSearchResult {
  documentId: string;
  slide: string;
  text: string;
  options: PptxFindOptions;
}

export async function findPresentation(
  client: PptxClient,
  state: PptxQuery,
  documentId: string,
  text: string,
  options: PptxFindOptions,
): Promise<PresentationSearchResult> {
  options = pptxFindOptions(options);
  return {
    ...(await client.execute({
      operation: "findPptx",
      revision: state.revision,
      slide: state.slide,
      text,
      options,
    })),
    documentId,
    slide: state.slide,
    text,
    options,
  };
}

export function replacePresentationMatches(
  client: PptxClient,
  result: PresentationSearchResult,
  snapshot: EditorSnapshot,
  profile: Record<string, string>,
  replacement: string,
  index?: number,
): Promise<PptxQuery> {
  checkPresentationSearch(result, snapshot, index);
  return client.execute({
    operation: "replacePptxMatches",
    revision: result.revision,
    slide: result.slide,
    text: result.text,
    options: result.options,
    replacement,
    profile,
    ...(index === undefined ? {} : { index }),
  });
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
