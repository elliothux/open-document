import {
  checkDocxComment,
  docxComments,
  docxCommentNavigation,
  type DocxCommentNavigation,
  type DocxCommentEdit,
  type DocxComments,
} from "./docx-comments.js";
import {
  docxOverview,
  type DocxOverview,
  checkDocxBookmark,
  type DocxBookmarkEdit,
} from "./docx-overview.js";
import { WasmSession } from "./session.js";
import { docxTracking, checkTrackingAuthor } from "./docx-tracking.js";
import {
  docxNotes,
  checkDocxNoteEdit,
  type DocxNoteEdit,
  checkDocxNoteCreate,
  checkDocxNoteIdentity,
  type DocxNoteCreate,
  type DocxNoteIdentity,
} from "./docx-notes.js";
import { integer, record } from "./validation.js";
import { editState, type EditState } from "./docx-format.js";
import {
  docxSelectionGeometry,
  type DocxSelectionGeometry,
} from "./docx-hit.js";

export interface DocxRevisions {
  revision: number;
  reason: string;
  items: {
    id: string;
    sourceId: string;
    kind:
      | "insert"
      | "delete"
      | "rowInsert"
      | "rowDelete"
      | "rowFormat"
      | "tableFormat"
      | "cellFormat"
      | "characterFormat"
      | "paragraphFormat"
      | "unsupported";
    element: string;
    author: string;
    date: string;
    text: string;
    paragraph: number | null;
    reason: string;
  }[];
}
export interface DocxRevisionEdit {
  action: "accept" | "reject";
  ids: readonly string[];
}
function identity(value: unknown): value is string {
  return (
    typeof value === "string" &&
    /^(0|[1-9]\d{0,9})$/.test(value) &&
    Number(value) <= 2147483647
  );
}
function text(value: unknown, max: number): value is string {
  return (
    typeof value === "string" && value.length <= max && value.isWellFormed()
  );
}
export function checkDocxRevisionEdit(value: unknown): void {
  const change = record(value);
  if (
    (change.action !== "accept" && change.action !== "reject") ||
    !Array.isArray(change.ids) ||
    !change.ids.length ||
    change.ids.length > 4096 ||
    !change.ids.every(identity) ||
    new Set(change.ids).size !== change.ids.length ||
    Object.keys(change).length !== 2 ||
    Object.keys(change).some((key) => key !== "action" && key !== "ids")
  )
    throw new Error("Invalid revision resolution");
}
export function docxRevisions(value: unknown): DocxRevisions {
  const result = record(value);
  if (
    !integer(result.revision, 0, 2147483647) ||
    !text(result.reason, 8192) ||
    !Array.isArray(result.items) ||
    result.items.length > 4096
  )
    throw new Error("Invalid revision catalog");
  const ids = new Set<string>();
  let units = 0;
  for (const entry of result.items) {
    const item = record(entry);
    if (
      !identity(item.id) ||
      ids.has(item.id) ||
      !text(item.sourceId, 128) ||
      ![
        "insert",
        "delete",
        "rowInsert",
        "rowDelete",
        "rowFormat",
        "tableFormat",
        "cellFormat",
        "characterFormat",
        "paragraphFormat",
        "unsupported",
      ].includes(String(item.kind)) ||
      typeof item.kind !== "string" ||
      !text(item.element, 64) ||
      !text(item.author, 255) ||
      !text(item.date, 128) ||
      !text(item.text, 32767) ||
      !text(item.reason, 8192) ||
      (item.paragraph !== null && !integer(item.paragraph, 0, 2147483647)) ||
      (!item.reason && (item.paragraph === null || item.kind === "unsupported"))
    )
      throw new Error("Invalid revision entry");
    ids.add(item.id);
    units += item.text.length;
    if (units > 1048576) throw new Error("Revision text exceeds budget");
  }
  return value as DocxRevisions;
}
export function docxRevisionGeometry(value: unknown): DocxSelectionGeometry {
  const geometry = docxSelectionGeometry(value);
  if (
    !integer(geometry.layoutId, 0, 2147483647) ||
    !integer(geometry.revision, 0, 2147483647) ||
    !geometry.rects.length ||
    geometry.rects.length > 65536 ||
    geometry.rects.some(
      (rect) =>
        !integer(rect.page, 0, 2147483647) ||
        !integer(rect.line, 0, 2147483647) ||
        rect.x < 0 ||
        rect.y < 0 ||
        rect.width <= 0,
    )
  )
    throw new Error("Invalid revision geometry");
  return geometry;
}

export class FoundationReviewSession extends WasmSession {
  private recording = false;
  protected override call(request: object): unknown {
    return super.call(
      this.recording
        ? { ...request, trackingDate: new Date().toISOString() }
        : request,
    );
  }
  tracking(revision: number) {
    const state = docxTracking(
      this.call({ operation: "docxTracking", revision }),
    );
    this.recording = state.enabled;
    return state;
  }
  setTracking(revision: number, author: string | null) {
    checkTrackingAuthor(author);
    const state = docxTracking(
      this.call({
        operation: "setDocxTracking",
        revision,
        author,
        date: new Date().toISOString(),
      }),
    );
    this.recording = state.enabled;
    return state;
  }
  insertNote(
    revision: number,
    note: DocxNoteCreate,
    profile: Record<string, string>,
  ) {
    checkDocxNoteCreate(note);
    return editState(
      this.call({ operation: "insertDocxNote", revision, note, profile }),
    );
  }
  removeNote(
    revision: number,
    note: DocxNoteIdentity,
    profile: Record<string, string>,
  ) {
    checkDocxNoteIdentity(note);
    return editState(
      this.call({ operation: "removeDocxNote", revision, note, profile }),
    );
  }
  notes(revision: number) {
    return docxNotes(this.call({ operation: "docxNotes", revision }));
  }
  editNote(
    revision: number,
    note: DocxNoteEdit,
    profile: Record<string, string>,
  ) {
    checkDocxNoteEdit(note);
    return editState(
      this.call({ operation: "editDocxNote", revision, note, profile }),
    );
  }
  revisionGeometry(
    revision: number,
    layoutId: number,
    id: string,
  ): DocxSelectionGeometry {
    if (!identity(id)) throw new Error("Invalid revision identity");
    return docxRevisionGeometry(
      this.call({
        operation: "docxRevisionGeometry",
        revision,
        layoutId,
        revisionId: id,
      }),
    );
  }
  overview(revision: number): DocxOverview {
    return docxOverview(this.call({ operation: "docxOverview", revision }));
  }
  comments(revision: number): DocxComments {
    return docxComments(this.call({ operation: "docxComments", revision }));
  }
  navigateComment(
    revision: number,
    direction: "previous" | "next",
  ): DocxCommentNavigation {
    if (direction !== "previous" && direction !== "next")
      throw new Error("Invalid comment navigation direction");
    return docxCommentNavigation(
      this.call({ operation: "navigateComment", revision, direction }),
    );
  }
  editComment(revision: number, change: DocxCommentEdit): EditState {
    checkDocxComment(change);
    return editState(
      this.call({ operation: "editDocxComment", revision, change }),
    );
  }
  editBookmark(revision: number, change: DocxBookmarkEdit): EditState {
    checkDocxBookmark(change);
    return editState(
      this.call({ operation: "editBookmark", revision, change }),
    );
  }

  revisions(revision: number): DocxRevisions {
    return docxRevisions(this.call({ operation: "docxRevisions", revision }));
  }
  resolveRevisions(revision: number, change: DocxRevisionEdit): EditState {
    checkDocxRevisionEdit(change);
    return editState(
      this.call({ operation: "resolveDocxRevisions", revision, change }),
    );
  }
}
