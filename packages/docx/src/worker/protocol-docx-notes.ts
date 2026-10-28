import type {
  DocxNoteEdit,
  DocxNoteCreate,
  DocxNoteIdentity,
  DocxEndnotePosition,
  DocxNoteKind,
  DocxNoteNumberingValue,
} from "../core/foundation.js";
export type DocxNoteRequest =
  | {
      operation: "noteNumbering";
      revision: number;
      kind: DocxNoteKind;
      section: number;
    }
  | {
      operation: "setNoteNumbering";
      revision: number;
      kind: DocxNoteKind;
      section: number;
      numbering: DocxNoteNumberingValue;
      profile: Record<string, string>;
    }
  | {
      operation: "setEndnotePosition";
      revision: number;
      position: DocxEndnotePosition;
      profile: Record<string, string>;
    }
  | {
      operation: "insertDocxNote";
      revision: number;
      note: DocxNoteCreate;
      profile: Record<string, string>;
    }
  | {
      operation: "removeDocxNote";
      revision: number;
      note: DocxNoteIdentity;
      profile: Record<string, string>;
    }
  | { operation: "docxNotes"; revision: number }
  | {
      operation: "editDocxNote";
      revision: number;
      note: DocxNoteEdit;
      profile: Record<string, string>;
    };
