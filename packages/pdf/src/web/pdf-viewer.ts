import { PdfView } from "./pdf-view.js";
import type { PdfClient } from "./pdf.js";
export type { PdfMatch, PdfEditorData } from "./pdf-viewer-state.js";

export type PdfViewer = Pick<
  PdfView,
  | "element"
  | "viewport"
  | "getSnapshot"
  | "subscribe"
  | "markSaved"
  | "markDownloaded"
  | "focus"
  | "setPaused"
  | "snapshot"
  | "displayedPage"
  | "refresh"
  | "goToPage"
  | "navigatePage"
  | "setZoom"
  | "selectText"
  | "selectedText"
  | "extractText"
  | "navigation"
  | "setReadingMode"
  | "selectRange"
  | "cancelSearch"
  | "search"
  | "nextMatch"
  | "close"
  | "copy"
  | "dispose"
>;

export const PdfViewer = {
  async create(
    root: HTMLElement,
    client: PdfClient,
    profile: Record<string, string> = {},
    signal?: AbortSignal,
  ): Promise<PdfViewer> {
    signal?.throwIfAborted();
    const viewer = new PdfView(
      client,
      await client.execute({ operation: "queryPdf" }),
      root,
      profile,
    );
    try {
      await viewer.refresh();
      signal?.throwIfAborted();
      return viewer;
    } catch (error) {
      await viewer.dispose();
      throw error;
    }
  },
};
