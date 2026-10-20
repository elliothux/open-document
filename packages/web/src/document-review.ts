import type { FoundationClient } from "./foundation.js";
import type { Connection } from "./connection.js";
import {
  headingSelection,
  type DocumentOverview,
} from "./document-selection.js";
import type { PageLayout } from "@open-document/wasm/preview";
import {
  docxRevisions,
  checkDocxRevisionEdit,
  type DocxRevisions,
  type DocxRevisionEdit,
  checkDocxBookmark,
  checkDocxComment,
  docxOverview,
  docxComments,
  docxCommentNavigation,
  editState,
  docxRevisionGeometry,
  type DocxSelectionGeometry,
  type DocxBookmarkEdit,
  type DocxCommentEdit,
  type DocxComments,
  type DocxCommentNavigation,
  type DocxOverview,
  type EditState,
} from "@open-document/wasm/foundation";

export interface DocumentComments extends DocxComments {
  documentId: string;
}
export interface DocumentRevisions extends DocxRevisions {
  documentId: string;
}

/** Review calls retain the same Worker protocol and validation as other document commands. */
export class FoundationReviewClient {
  constructor(protected readonly connection: Connection) {}
  async revisionGeometry(
    revision: number,
    layoutId: number,
    id: string,
  ): Promise<DocxSelectionGeometry> {
    if (
      typeof id !== "string" ||
      !/^(0|[1-9]\d{0,9})$/.test(id) ||
      Number(id) > 2147483647
    )
      throw new Error("Invalid revision identity");
    return docxRevisionGeometry(
      await this.connection.request({
        operation: "docxRevisionGeometry",
        revision,
        layoutId,
        revisionId: id,
      }),
    );
  }
  async revisions(revision: number): Promise<DocxRevisions> {
    return docxRevisions(
      await this.connection.request({ operation: "docxRevisions", revision }),
    );
  }
  async resolveRevisions(
    revision: number,
    change: DocxRevisionEdit,
  ): Promise<EditState> {
    checkDocxRevisionEdit(change);
    return editState(
      await this.connection.request({
        operation: "resolveDocxRevisions",
        revision,
        change,
      }),
    );
  }
  async overview(revision: number): Promise<DocxOverview> {
    return docxOverview(
      await this.connection.request({ operation: "docxOverview", revision }),
    );
  }
  async comments(revision: number): Promise<DocxComments> {
    return docxComments(
      await this.connection.request({ operation: "docxComments", revision }),
    );
  }
  async navigateComment(
    revision: number,
    direction: "previous" | "next",
  ): Promise<DocxCommentNavigation> {
    if (direction !== "previous" && direction !== "next")
      throw new Error("Invalid comment navigation direction");
    return docxCommentNavigation(
      await this.connection.request({
        operation: "navigateComment",
        revision,
        direction,
      }),
    );
  }
  async editBookmark(
    revision: number,
    change: DocxBookmarkEdit,
  ): Promise<EditState> {
    checkDocxBookmark(change);
    return editState(
      await this.connection.request({
        operation: "editBookmark",
        revision,
        change,
      }),
    );
  }
  async editComment(
    revision: number,
    change: DocxCommentEdit,
  ): Promise<EditState> {
    checkDocxComment(change);
    return editState(
      await this.connection.request({
        operation: "editDocxComment",
        revision,
        change,
      }),
    );
  }
}

/** Review catalogs and commands use the editor's existing input and output queue. */
export abstract class DocumentReview {
  private commentFocus: Readonly<{ id: string }> | undefined;
  getCommentFocus(): Readonly<{ id: string }> | undefined {
    return this.commentFocus;
  }
  protected constructor(
    protected readonly review: {
      client: FoundationClient;
      read<T>(operation: () => Promise<T>): Promise<T>;
      edit(operation: () => Promise<EditState>): Promise<void>;
      snapshot(): { revision: number; documentId: string };
      layout(): PageLayout;
    },
  ) {}
  protected abstract showRevisionGeometry(
    geometry: DocxSelectionGeometry,
  ): Promise<void>;
  showRevision(source: DocumentRevisions, id: string): Promise<void> {
    const check = () => {
      const current = this.review.snapshot(),
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
    return this.review
      .read(async () => {
        // Read-only review failures leave the editor's input queue usable.
        try {
          check();
          const layout = this.review.layout(),
            geometry = await this.review.client.revisionGeometry(
              source.revision,
              layout.id,
              id,
            );
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
          await this.showRevisionGeometry(geometry);
          return { ok: true as const };
        } catch (error) {
          return { ok: false as const, error };
        }
      })
      .then((result) => {
        if (!result.ok) throw result.error;
      });
  }
  revisions(): Promise<DocumentRevisions> {
    return this.review.read(async () => ({
      ...(await this.review.client.revisions(this.review.snapshot().revision)),
      documentId: this.review.snapshot().documentId,
    }));
  }
  resolveRevisions(
    source: DocumentRevisions,
    change: DocxRevisionEdit,
  ): Promise<void> {
    const current = this.review.snapshot();
    if (
      source.documentId !== current.documentId ||
      source.revision !== current.revision
    )
      return Promise.reject(
        new Error("Revision catalog belongs to an older document state"),
      );
    return this.review.edit(() => {
      const current = this.review.snapshot();
      if (
        source.documentId !== current.documentId ||
        source.revision !== current.revision
      )
        throw new Error("Revision catalog belongs to an older document state");
      return this.review.client.resolveRevisions(source.revision, change);
    });
  }
  overview(): Promise<DocumentOverview> {
    return this.review.read(async () => ({
      ...(await this.review.client.overview(this.review.snapshot().revision)),
      documentId: this.review.snapshot().documentId,
    }));
  }
  selectHeading(result: DocumentOverview, index: number): Promise<void> {
    return this.review.edit(() =>
      this.review.client.selectDocx(
        result.revision,
        headingSelection(result, this.review.snapshot(), index),
      ),
    );
  }
  comments(): Promise<DocumentComments> {
    return this.review.read(async () => ({
      ...(await this.review.client.comments(this.review.snapshot().revision)),
      documentId: this.review.snapshot().documentId,
    }));
  }
  editBookmark(change: DocxBookmarkEdit): Promise<void> {
    return this.review.edit(() =>
      this.review.client.editBookmark(this.review.snapshot().revision, change),
    );
  }
  editComment(change: DocxCommentEdit): Promise<void> {
    return this.review.edit(async () => {
      const state = await this.review.client.editComment(
        this.review.snapshot().revision,
        change,
      );
      this.commentFocus =
        change.action === "goTo" ? Object.freeze({ id: change.id }) : undefined;
      return state;
    });
  }
  navigateComment(direction: "previous" | "next"): Promise<void> {
    return this.review.edit(async () => {
      const result = await this.review.client.navigateComment(
        this.review.snapshot().revision,
        direction,
      );
      this.commentFocus =
        result.comment === null
          ? undefined
          : Object.freeze({ id: result.comment });
      return result.state;
    });
  }
}
