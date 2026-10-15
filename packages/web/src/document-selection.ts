import { DocumentError, type EditState } from "@open-document/wasm/foundation";
import type { FoundationClient } from "./foundation.js";
import type {
  DocxPosition,
  DocxSelection,
  DocxSearchResult,
} from "@open-document/wasm/foundation";
import type { EditorSnapshot } from "./editor-state.js";

export interface DocumentSearchResult extends DocxSearchResult {
  documentId: string;
}

export function searchSelections(
  result: DocumentSearchResult,
  snapshot: EditorSnapshot,
  index?: number,
): DocxSelection[] {
  const reject = (message: string): never => {
    throw new DocumentError("stale-search", message, "", -1);
  };
  if (
    result.documentId !== snapshot.documentId ||
    result.revision !== snapshot.revision
  )
    reject("Document changed; find again before using this result");
  if (index === undefined && result.truncated)
    reject("Narrow the search before replacing all matches");
  const matches =
    index === undefined ? result.matches : [result.matches[index]];
  return matches.map((item) => {
    if (!item || item.reason)
      return reject(item?.reason || "Search match is missing");
    return item.selection;
  });
}

export function sameDocxSelection(
  a: DocxSelection | null,
  b: DocxSelection,
): boolean {
  const same = (a: DocxPosition, b: DocxPosition) =>
    a.paragraph === b.paragraph &&
    a.offset === b.offset &&
    a.affinity === b.affinity &&
    a.bidiLevel === b.bidiLevel &&
    a.frameStart === b.frameStart;
  return a !== null && same(a.anchor, b.anchor) && same(a.focus, b.focus);
}

export async function docxSelectionDescription(
  client: FoundationClient,
  state: EditState,
  page: number,
  stopped: boolean,
): Promise<string> {
  if (stopped) return "Selection unavailable while editing is stopped";
  if (state.compositionId !== null) return "Text composition in progress";
  const selection = state.selection;
  if (!selection) return "Focus document text input to start editing";
  if (
    selection.anchor.paragraph === selection.focus.paragraph &&
    selection.anchor.offset === selection.focus.offset
  )
    return `Insertion point on page ${page + 1}`;
  try {
    return `Selected text: ${await client.selectedText(state.revision, selection)}`;
  } catch (error) {
    if (
      !(error instanceof DocumentError) ||
      (error.code !== "protected-content" && error.code !== "limit-exceeded")
    )
      throw error;
    return `Selected content is unavailable: ${error.message}`;
  }
}
