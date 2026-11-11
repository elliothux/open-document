import type { DocxNoteKind, DocxNoteNumberingValue } from "./docx-notes.js";
import type { DocxFlow } from "./preview.js";

export interface DocxFlowNote {
  kind: DocxNoteKind;
  key: string;
  paragraph: number;
  node: number;
  numbering: {
    format: DocxNoteNumberingValue["format"];
    value: number;
    restart: DocxNoteNumberingValue["restart"];
    marker: number;
  };
  content: DocxFlow["paragraphs"];
}
