import type { DocxNoteEdit } from "@open-document/wasm/foundation";
export type DocxNoteRequest =
  | { operation: "docxNotes"; revision: number }
  | { operation: "editDocxNote"; revision: number; note: DocxNoteEdit };
