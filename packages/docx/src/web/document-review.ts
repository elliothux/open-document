import type { DocumentHost } from "./document-host.js";
import type { FoundationClient } from "./foundation.js";
import {
  headingSelection,
  type DocumentOverview,
} from "./document-selection.js";

import {
  checkTrackingAuthor,
  type DocxRevisions,
  type DocxRevisionEdit,
  docxNoteNumbering,
  checkNoteNumbering,
  type DocxNoteKind,
  type DocxNoteNumbering,
  type DocxNoteNumberingValue,
  checkEndnotePosition,
  type DocxEndnotePosition,
  checkDocxNoteEdit,
  type DocxNotes,
  type DocxNoteEdit,
  checkDocxNoteCreate,
  checkDocxNoteIdentity,
  type DocxNoteCreate,
  type DocxNoteIdentity,
  type DocxSelectionGeometry,
  type DocxBookmarkEdit,
  type DocxCommentEdit,
  type DocxComments,
  type EditState,
} from "../core/foundation.js";

export interface DocumentComments extends DocxComments {
  documentId: string;
}
export interface DocumentNotes extends DocxNotes {
  documentId: string;
}
export interface DocumentNoteNumbering extends DocxNoteNumbering {
  documentId: string;
}
export interface DocumentRevisions extends DocxRevisions {
  documentId: string;
}

export function createDocumentReview(
  client: FoundationClient,
  host: DocumentHost & {
    shownRevision(): string | undefined;
    showRevisionGeometry(
      id: string,
      geometry: DocxSelectionGeometry,
    ): Promise<void>;
  },
) {
  let commentFocus: Readonly<{ id: string }> | undefined;
  function checkNoteSource(
    source: DocumentNotes,
    note: DocxNoteIdentity,
  ): void {
    const current = host.snapshot();
    if (
      source.documentId !== current.documentId ||
      source.revision !== current.revision
    )
      throw new Error("Note catalog belongs to an older document state");
    const entry = source.entries.find(
      (entry) => entry.kind === note.kind && entry.id === note.id,
    );
    if (!entry || entry.reason)
      throw new Error("This note requires structured editing");
  }
  function noteCommand(
    check: () => void,
    command: () => Promise<EditState>,
  ): Promise<void> {
    try {
      check();
    } catch (error) {
      return Promise.reject(error);
    }
    let failure: { error: unknown } | undefined;
    return host
      .edit(async () => {
        try {
          check();
          return await command();
        } catch (error) {
          // Refresh authoritative state before reporting a rejected note transaction.
          failure = { error };
          return client.execute({ operation: "editState" });
        }
      })
      .then(() => {
        if (failure) throw failure.error;
      });
  }
  return {
    tracking() {
      return host.read(() =>
        client.execute({
          operation: "tracking",
          revision: host.snapshot().revision,
        }),
      );
    },
    setTracking(author: string | null): Promise<void> {
      checkTrackingAuthor(author);
      return host.edit(async () => {
        await client.execute({
          operation: "setTracking",
          revision: host.snapshot().revision,
          author: author,
        });
        return client.execute({ operation: "editState" });
      });
    },
    notes(): Promise<DocumentNotes> {
      return host
        .read(async () => {
          try {
            const value = {
              ...(await client.execute({
                operation: "notes",
                revision: host.snapshot().revision,
              })),
              documentId: host.snapshot().documentId,
            };
            return { ok: true as const, value };
          } catch (error) {
            return { ok: false as const, error };
          }
        })
        .then((result) => {
          if (!result.ok) throw result.error;
          return result.value;
        });
    },
    noteNumbering(
      kind: DocxNoteKind,
      section: number,
    ): Promise<DocumentNoteNumbering> {
      return host
        .read(async () => {
          try {
            const value = {
              ...(await client.execute({
                operation: "noteNumbering",
                revision: host.snapshot().revision,
                kind: kind,
                section: section,
              })),
              documentId: host.snapshot().documentId,
            };
            return { ok: true as const, value };
          } catch (error) {
            return { ok: false as const, error };
          }
        })
        .then((result) => {
          if (!result.ok) throw result.error;
          return result.value;
        });
    },
    setNoteNumbering(
      source: DocumentNoteNumbering,
      value: DocxNoteNumberingValue,
    ): Promise<void> {
      return noteCommand(
        () => {
          checkNoteNumbering(value);
          docxNoteNumbering(source);
          const current = host.snapshot();
          if (
            source.documentId !== current.documentId ||
            source.revision !== current.revision
          )
            throw new Error(
              "Note numbering belongs to an older document state",
            );
          if (source.value === null || source.reason)
            throw new Error("Note numbering requires structured editing");
        },
        () =>
          client.execute({
            operation: "setNoteNumbering",
            revision: source.revision,
            kind: source.kind,
            section: source.section,
            numbering: value,
            profile: host.layout().profile,
          }),
      );
    },
    editNote(source: DocumentNotes, note: DocxNoteEdit): Promise<void> {
      const check = () => {
        checkDocxNoteEdit(note);
        checkNoteSource(source, note);
      };
      return noteCommand(check, () =>
        client.execute({
          operation: "editNote",
          revision: source.revision,
          note: note,
          profile: host.layout().profile,
        }),
      );
    },
    setEndnotePosition(
      source: DocumentNotes,
      position: DocxEndnotePosition,
    ): Promise<void> {
      return noteCommand(
        () => {
          checkEndnotePosition(position);
          const current = host.snapshot();
          if (
            source.documentId !== current.documentId ||
            source.revision !== current.revision
          )
            throw new Error("Note catalog belongs to an older document state");
          if (source.endnotes.reason || source.endnotes.position === null)
            throw new Error("Endnote settings require structured editing");
        },
        () =>
          client.execute({
            operation: "setEndnotePosition",
            revision: source.revision,
            position: position,
            profile: host.layout().profile,
          }),
      );
    },
    insertNote(note: DocxNoteCreate): Promise<void> {
      return noteCommand(
        () => checkDocxNoteCreate(note),
        () =>
          client.execute({
            operation: "insertNote",
            revision: host.snapshot().revision,
            note: note,
            profile: host.layout().profile,
          }),
      );
    },
    removeNote(source: DocumentNotes, note: DocxNoteIdentity): Promise<void> {
      return noteCommand(
        () => {
          checkDocxNoteIdentity(note);
          checkNoteSource(source, note);
        },
        () =>
          client.execute({
            operation: "removeNote",
            revision: source.revision,
            note: note,
            profile: host.layout().profile,
          }),
      );
    },
    getCommentFocus(): Readonly<{ id: string }> | undefined {
      return commentFocus;
    },
    getShownRevision: host.shownRevision,
    showRevision(source: DocumentRevisions, id: string): Promise<void> {
      const check = () => {
        const current = host.snapshot(),
          entry = source.items.find((item) => item.id === id);
        if (
          source.documentId !== current.documentId ||
          source.revision !== current.revision ||
          !entry ||
          entry.reason
        )
          throw new Error(
            entry?.reason ||
              "Revision catalog belongs to an older document state",
          );
      };
      try {
        check();
      } catch (error) {
        return Promise.reject(error);
      }
      return host
        .read(async () => {
          // Read-only review failures leave the editor's input queue usable.
          try {
            check();
            const layout = host.layout(),
              geometry = await client.execute({
                operation: "revisionGeometry",
                revision: source.revision,
                layoutId: layout.id,
                id: id,
              });
            if (
              geometry.layoutId !== layout.id ||
              geometry.revision !== source.revision ||
              !geometry.rects.length ||
              geometry.rects.length > 65536 ||
              geometry.rects.some((rect) => {
                const page = layout.regions[rect.page];
                return (
                  !page ||
                  rect.x < 0 ||
                  rect.y < 0 ||
                  rect.width <= 0 ||
                  rect.x + rect.width > page.width ||
                  rect.y + rect.height > page.height
                );
              })
            )
              throw new Error("Invalid revision geometry");
            await host.showRevisionGeometry(id, geometry);
            return { ok: true as const };
          } catch (error) {
            return { ok: false as const, error };
          }
        })
        .then((result) => {
          if (!result.ok) throw result.error;
        });
    },
    revisions(): Promise<DocumentRevisions> {
      return host.read(async () => ({
        ...(await client.execute({
          operation: "revisions",
          revision: host.snapshot().revision,
        })),
        documentId: host.snapshot().documentId,
      }));
    },
    resolveRevisions(
      source: DocumentRevisions,
      change: DocxRevisionEdit,
    ): Promise<void> {
      const current = host.snapshot();
      if (
        source.documentId !== current.documentId ||
        source.revision !== current.revision
      )
        return Promise.reject(
          new Error("Revision catalog belongs to an older document state"),
        );
      return host.edit(() => {
        const current = host.snapshot();
        if (
          source.documentId !== current.documentId ||
          source.revision !== current.revision
        )
          throw new Error(
            "Revision catalog belongs to an older document state",
          );
        return client.execute({
          operation: "resolveRevisions",
          revision: source.revision,
          change: change,
        });
      });
    },
    overview(): Promise<DocumentOverview> {
      return host.read(async () => ({
        ...(await client.execute({
          operation: "overview",
          revision: host.snapshot().revision,
        })),
        documentId: host.snapshot().documentId,
      }));
    },
    selectHeading(result: DocumentOverview, index: number): Promise<void> {
      return host.edit(() =>
        client.execute({
          operation: "selectDocx",
          revision: result.revision,
          selection: headingSelection(result, host.snapshot(), index),
        }),
      );
    },
    comments(): Promise<DocumentComments> {
      return host.read(async () => ({
        ...(await client.execute({
          operation: "comments",
          revision: host.snapshot().revision,
        })),
        documentId: host.snapshot().documentId,
      }));
    },
    editBookmark(change: DocxBookmarkEdit): Promise<void> {
      return host.edit(() =>
        client.execute({
          operation: "editBookmark",
          revision: host.snapshot().revision,
          change: change,
        }),
      );
    },
    editComment(change: DocxCommentEdit): Promise<void> {
      return host.edit(async () => {
        const state = await client.execute({
          operation: "editComment",
          revision: host.snapshot().revision,
          change: change,
        });
        commentFocus =
          change.action === "goTo"
            ? Object.freeze({ id: change.id })
            : undefined;
        return state;
      });
    },
    navigateComment(direction: "previous" | "next"): Promise<void> {
      return host.edit(async () => {
        const result = await client.execute({
          operation: "navigateComment",
          revision: host.snapshot().revision,
          direction: direction,
        });
        commentFocus =
          result.comment === null
            ? undefined
            : Object.freeze({ id: result.comment });
        return result.state;
      });
    },
  };
}
