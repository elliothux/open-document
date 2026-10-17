import type { FoundationClient } from "./foundation.js";
import type { Connection } from "./connection.js";
import type { DocumentOverview } from "./document-selection.js";
import {
  checkDocxBookmark,
  checkDocxComment,
  docxOverview,
  docxComments,
  docxCommentNavigation,
  editState,
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

/** Review calls retain the same Worker protocol and validation as other document commands. */
export class FoundationReviewClient {
  constructor(protected readonly connection: Connection) {}
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
export class DocumentReview {
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
    },
  ) {}
  overview(): Promise<DocumentOverview> {
    return this.review.read(async () => ({
      ...(await this.review.client.overview(this.review.snapshot().revision)),
      documentId: this.review.snapshot().documentId,
    }));
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
