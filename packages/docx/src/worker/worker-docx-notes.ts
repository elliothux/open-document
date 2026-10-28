import type { FoundationSession } from "../core/foundation.js";
import type { DocxNoteRequest } from "./protocol-docx-notes.js";

export function noteOperation(
  foundation: FoundationSession,
  request: DocxNoteRequest,
): unknown {
  switch (request.operation) {
    case "noteNumbering":
      return foundation.noteNumbering(
        request.revision,
        request.kind,
        request.section,
      );
    case "setNoteNumbering":
      return foundation.setNoteNumbering(
        request.revision,
        request.kind,
        request.section,
        request.numbering,
        request.profile,
      );
    case "docxNotes":
      return foundation.notes(request.revision);
    case "setEndnotePosition":
      return foundation.setEndnotePosition(
        request.revision,
        request.position,
        request.profile,
      );
    case "insertDocxNote":
      return foundation.insertNote(
        request.revision,
        request.note,
        request.profile,
      );
    case "removeDocxNote":
      return foundation.removeNote(
        request.revision,
        request.note,
        request.profile,
      );
    case "editDocxNote":
      return foundation.editNote(
        request.revision,
        request.note,
        request.profile,
      );
  }
}
