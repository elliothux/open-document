import type {
  DocxNoteEdit,
  DocxNoteCreate,
  DocxNoteIdentity,
} from "@open-document/wasm/foundation";
export type DocxNoteRequest =
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
