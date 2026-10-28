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
