import { DocumentError, type EditState } from "../core/foundation.js";
import type { FoundationClient } from "./foundation.js";
import type {
  DocxPosition,
  DocxSelection,
  DocxSearchResult,
  DocxHit,
  DocxOverview,
} from "../core/foundation.js";
import type { EditorSnapshot } from "@open-document/web-core/editor-state";
import type { PageLayout } from "../core/preview.js";
import type {
  DocxSelectionView,
  DocxSelectionViewRequest,
} from "../core/docx-hit.js";

export type DocumentOverview = DocxOverview & { documentId: string };

export function headingSelection(
  result: DocumentOverview,
  snapshot: Pick<EditorSnapshot, "revision" | "documentId">,
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
  if (initial && !extend && hit.drawing) return hit.drawing;
  return {
    anchor:
      extend && current.selection ? current.selection.anchor : hit.position,
    focus: hit.position,
  };
}

export function docxSelectionRequest(
  state: EditState,
): DocxSelectionViewRequest | undefined {
  const selection = state.selection;
  if (!selection) return undefined;
  const formatTable = !!state.formatting?.table;
  return {
    revision: state.revision,
    selection,
    formatTable,
    describeText:
      state.compositionId === null &&
      state.drawingGestureId === null &&
      (formatTable || !state.formatting?.cellSelection.value),
  };
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
  if (!line) return state;
  const position = {
    paragraph: line.paragraph,
    offset: line.start,
    affinity: "after" as const,
  };
  return client.execute({
    operation: "selectDocx",
    revision: state.revision,
    selection: {
      anchor: position,
      focus: position,
    },
  });
}

export function docxInputReadOnly(
  state: EditState,
  layout: PageLayout,
): boolean {
  return (
    !!state.readOnlyReason ||
    !!state.formatting?.inputReason ||
    !layout.semantics.some((page) =>
      page.lines.some((line) => !line.readOnlyReason),
    )
  );
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

export function docxSelectionDescription(
  state: EditState,
  page: number,
  stopped: boolean,
  view: DocxSelectionView | undefined,
): string {
  if (stopped) return "Selection unavailable while editing is stopped";
  if (state.compositionId !== null) return "Text composition in progress";
  if (state.drawingGestureId !== null) return "Drawing gesture in progress";
  const selection = state.selection;
  if (!selection) return "Focus document text input to start editing";
  const cells = state.formatting?.cellSelection.value;
  if (cells) return `Selected table cells: ${cells.count}`;
  if (
    selection.anchor.paragraph === selection.focus.paragraph &&
    selection.anchor.offset === selection.focus.offset
  )
    return `Insertion point on page ${page + 1}`;
  if (!view) throw new Error("Missing DOCX selection view");
  return view.selectionError
    ? `Selected content is unavailable: ${view.selectionError}`
    : `Selected text: ${view.selectedText.replaceAll("\ufffc", "[drawing]")}`;
}
