import {
  checkDocxComment,
  type DocxCommentNavigation,
  type DocxCommentEdit,
  type DocxComments,
} from "./docx-comments.js";
import {
  type DocxOverview,
  checkDocxBookmark,
  type DocxBookmarkEdit,
} from "./docx-overview.js";
import { type DocxTracking, checkTrackingAuthor } from "./docx-tracking.js";
import {
  type DocxNotes,
  type DocxNoteNumbering,
  checkNoteNumbering,
  type DocxNoteKind,
  type DocxNoteNumberingValue,
  checkDocxNoteEdit,
  type DocxNoteEdit,
  checkDocxNoteCreate,
  checkDocxNoteIdentity,
  type DocxNoteCreate,
  type DocxNoteIdentity,
  checkEndnotePosition,
  type DocxEndnotePosition,
} from "./docx-notes.js";

import { type EditState } from "./docx-format.js";
import { type DocxSelectionGeometry } from "./docx-hit.js";
import {
  type DocxRevisions,
  type DocxRevisionEdit,
  checkDocxRevisionEdit,
} from "./docx-revisions.js";
import type { DocxRuntime } from "./docx-session.js";
import { checkDocxRevisionIdentity } from "./docx-revisions.js";
export const docxReviewCommands = {
  tracking(session: DocxRuntime, { revision }: { revision: number }) {
    const state = session.call<DocxTracking>({
      operation: "docxTracking",
      revision,
    });
    session.setRecording(state.enabled);
    return state;
  },
  setTracking(
    session: DocxRuntime,
    { revision, author }: { revision: number; author: string | null },
  ) {
    checkTrackingAuthor(author);
    const state = session.call<DocxTracking>({
      operation: "setDocxTracking",
      revision,
      author,
      date: new Date().toISOString(),
    });
    session.setRecording(state.enabled);
    return state;
  },
  insertNote(
    session: DocxRuntime,
    {
      revision,
      note,
      profile,
    }: {
      revision: number;
      note: DocxNoteCreate;
      profile: Record<string, string>;
    },
  ) {
    checkDocxNoteCreate(note);
    return session.call<EditState>({
      operation: "insertDocxNote",
      revision,
      note,
      profile,
    });
  },
  removeNote(
    session: DocxRuntime,
    {
      revision,
      note,
      profile,
    }: {
      revision: number;
      note: DocxNoteIdentity;
      profile: Record<string, string>;
    },
  ) {
    checkDocxNoteIdentity(note);
    return session.call<EditState>({
      operation: "removeDocxNote",
      revision,
      note,
      profile,
    });
  },
  notes(session: DocxRuntime, { revision }: { revision: number }) {
    return session.call<DocxNotes>({ operation: "docxNotes", revision });
  },
  noteNumbering(
    session: DocxRuntime,
    {
      revision,
      kind,
      section,
    }: { revision: number; kind: DocxNoteKind; section: number },
  ) {
    return session.call<DocxNoteNumbering>({
      operation: "noteNumbering",
      revision,
      kind,
      section,
    });
  },
  setNoteNumbering(
    session: DocxRuntime,
    {
      revision,
      kind,
      section,
      numbering,
      profile,
    }: {
      revision: number;
      kind: DocxNoteKind;
      section: number;
      numbering: DocxNoteNumberingValue;
      profile: Record<string, string>;
    },
  ) {
    checkNoteNumbering(numbering);
    return session.call<EditState>({
      operation: "setNoteNumbering",
      revision,
      kind,
      section,
      numbering,
      profile,
    });
  },
  setEndnotePosition(
    session: DocxRuntime,
    {
      revision,
      position,
      profile,
    }: {
      revision: number;
      position: DocxEndnotePosition;
      profile: Record<string, string>;
    },
  ) {
    checkEndnotePosition(position);
    return session.call<EditState>({
      operation: "setEndnotePosition",
      revision,
      position,
      profile,
    });
  },
  editNote(
    session: DocxRuntime,
    {
      revision,
      note,
      profile,
    }: {
      revision: number;
      note: DocxNoteEdit;
      profile: Record<string, string>;
    },
  ) {
    checkDocxNoteEdit(note);
    return session.call<EditState>({
      operation: "editDocxNote",
      revision,
      note,
      profile,
    });
  },
  revisionGeometry(
    session: DocxRuntime,
    {
      revision,
      layoutId,
      id,
    }: { revision: number; layoutId: number; id: string },
  ): DocxSelectionGeometry {
    checkDocxRevisionIdentity(id);
    return session.call<DocxSelectionGeometry>({
      operation: "docxRevisionGeometry",
      revision,
      layoutId,
      revisionId: id,
    });
  },
  overview(
    session: DocxRuntime,
    { revision }: { revision: number },
  ): DocxOverview {
    return session.call<DocxOverview>({ operation: "docxOverview", revision });
  },
  comments(
    session: DocxRuntime,
    { revision }: { revision: number },
  ): DocxComments {
    return session.call<DocxComments>({ operation: "docxComments", revision });
  },
  navigateComment(
    session: DocxRuntime,
    {
      revision,
      direction,
    }: { revision: number; direction: "previous" | "next" },
  ): DocxCommentNavigation {
    if (direction !== "previous" && direction !== "next")
      throw new Error("Invalid comment navigation direction");
    return session.call<DocxCommentNavigation>({
      operation: "navigateComment",
      revision,
      direction,
    });
  },
  editComment(
    session: DocxRuntime,
    { revision, change }: { revision: number; change: DocxCommentEdit },
  ): EditState {
    checkDocxComment(change);
    return session.call<EditState>({
      operation: "editDocxComment",
      revision,
      change,
    });
  },
  editBookmark(
    session: DocxRuntime,
    { revision, change }: { revision: number; change: DocxBookmarkEdit },
  ): EditState {
    checkDocxBookmark(change);
    return session.call<EditState>({
      operation: "editBookmark",
      revision,
      change,
    });
  },
  revisions(
    session: DocxRuntime,
    { revision }: { revision: number },
  ): DocxRevisions {
    return session.call<DocxRevisions>({
      operation: "docxRevisions",
      revision,
    });
  },
  resolveRevisions(
    session: DocxRuntime,
    { revision, change }: { revision: number; change: DocxRevisionEdit },
  ): EditState {
    checkDocxRevisionEdit(change, session.inputLimits().revisionEntries);
    return session.call<EditState>({
      operation: "resolveDocxRevisions",
      revision,
      change,
    });
  },
};
