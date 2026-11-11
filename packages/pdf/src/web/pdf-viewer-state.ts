import { EditorState } from "@open-document/web-core/editor-state";
import type { PdfQuery } from "../core/pdf.js";

export interface PdfMatch {
  page: string;
  start: number;
  end: number;
}

export interface PdfEditorData {
  readonly readingMode: "single" | "continuous" | "double";
  readonly query: PdfQuery;
  readonly matches: readonly PdfMatch[];
  readonly matchIndex: number;
  readonly searching: boolean;
  readonly searchPage: number;
  readonly property: string;
  readonly propertyReason: string;
  readonly applying: boolean;
}

export interface PdfViewHooks {
  inputState?(): {
    draft: boolean;
    composition: boolean;
    dragging?: boolean;
    property: string;
    propertyReason: string;
    applying: boolean;
  };
  pauseChanged?(): void;
  checkDraft?(): void;
  checkClose?(): void;
  stateChanged?(): void;
}

export function createPdfEditorState(
  state: PdfQuery,
): EditorState<PdfEditorData> {
  return new EditorState("pdf", {
    revision: state.revision,
    canUndo: state.canUndo,
    canRedo: state.canRedo,
    page: state.pages.findIndex((page) => page.id === state.page),
    pageCount: state.pages.length,
    selection: "",
    readOnlyReason: state.readOnlyReason,
    diagnostics: state.diagnostics,
    data: {
      readingMode: "single",
      query: state,
      matches: [],
      matchIndex: -1,
      searching: false,
      searchPage: 0,
      property: "",
      propertyReason: "",
      applying: false,
    },
  });
}
