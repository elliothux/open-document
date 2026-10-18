import { DocumentError, type EditState } from "@open-document/wasm/foundation";
import type { FoundationClient } from "./foundation.js";
import type {
  DocxPosition,
  DocxSelection,
  DocxSearchResult,
  DocxHit,
  DocxOverview,
} from "@open-document/wasm/foundation";
import type { EditorSnapshot } from "./editor-state.js";
import type { PageLayout } from "@open-document/wasm/preview";

export type DocumentOverview = DocxOverview & { documentId: string };

export function headingSelection(
  result: DocumentOverview,
  snapshot: EditorSnapshot,
  index: number,
): DocxSelection {
  const heading = result.headings[index];
  if (
    result.documentId !== snapshot.documentId ||
    result.revision !== snapshot.revision ||
    !heading ||
    heading.reason
  )
    throw new DocumentError(
      "stale-overview",
      heading?.reason || "Document changed; refresh headings before navigation",
      "",
      -1,
    );
  const position: DocxPosition = {
    paragraph: heading.paragraph,
    offset: 0,
    affinity: "after",
  };
  return { anchor: position, focus: position };
}

export function pointerDocxSelection(
  hit: DocxHit,
  current: EditState,
  initial: boolean,
  extend: boolean,
): DocxSelection {
  if (!hit.position) throw new Error(hit.reason);
  if (initial && !extend && hit.picture) return hit.picture;
  return {
    anchor:
      extend && current.selection ? current.selection.anchor : hit.position,
    focus: hit.position,
  };
}

export async function queryDocxSelectionGeometry(
  client: FoundationClient,
  state: EditState,
  layout: PageLayout,
  assertOpen: () => void,
) {
  const selection = state.selection;
  const layoutId = layout.id,
    revision = layout.revision;
  const caret = selection
    ? await client.caret(layoutId, selection.focus)
    : undefined;
  assertOpen();
  const geometry = selection
    ? await client.selectionGeometry(layoutId, selection)
    : undefined;
  assertOpen();
  if (
    (caret && (caret.layoutId !== layoutId || caret.revision !== revision)) ||
    (geometry &&
      (geometry.layoutId !== layoutId || geometry.revision !== revision))
  )
    throw new Error("Selection geometry belongs to a stale layout");
  const formatting =
    selection && state.formatting?.table
      ? await client.queryFormatting(state.revision, selection)
      : state.formatting;
  assertOpen();
  return { caret, geometry, formatting };
}

export async function selectFirstDocxPosition(
  client: FoundationClient,
  state: EditState,
  layout: PageLayout,
  page: number,
): Promise<EditState> {
  let line = layout.semantics[page]?.lines.find((line) => !line.readOnlyReason);
  if (!line)
    for (const semantics of layout.semantics) {
      line = semantics.lines.find((line) => !line.readOnlyReason);
      if (line) break;
    }
  if (!line) throw new Error("This page has no editable text position");
  const position = {
    paragraph: line.paragraph,
    offset: line.start,
    affinity: "after" as const,
  };
  return client.selectDocx(state.revision, {
    anchor: position,
    focus: position,
  });
}

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

export function assertDocxSelection(
  current: EditState,
  revision: number,
  b: DocxSelection,
): void {
  const a = current.selection;
  const same = (a: DocxPosition, b: DocxPosition) =>
    a.paragraph === b.paragraph &&
    a.offset === b.offset &&
    a.affinity === b.affinity &&
    a.bidiLevel === b.bidiLevel &&
    a.frameStart === b.frameStart;
  if (
    current.revision !== revision ||
    a === null ||
    !same(a.anchor, b.anchor) ||
    !same(a.focus, b.focus)
  )
    throw new Error("Document or selection changed during clipboard write");
}

export async function docxSelectionDescription(
  client: FoundationClient,
  state: EditState,
  page: number,
  stopped: boolean,
): Promise<string> {
  if (stopped) return "Selection unavailable while editing is stopped";
  if (state.compositionId !== null) return "Text composition in progress";
  if (state.pictureResizeId !== null) return "Picture resize in progress";
  const selection = state.selection;
  if (!selection) return "Focus document text input to start editing";
  if (
    selection.anchor.paragraph === selection.focus.paragraph &&
    selection.anchor.offset === selection.focus.offset
  )
    return `Insertion point on page ${page + 1}`;
  try {
    return `Selected text: ${(await client.selectedText(state.revision, selection)).replaceAll("\ufffc", "[image]")}`;
  } catch (error) {
    if (
      !(error instanceof DocumentError) ||
      (error.code !== "protected-content" && error.code !== "limit-exceeded")
    )
      throw error;
    return `Selected content is unavailable: ${error.message}`;
  }
}
