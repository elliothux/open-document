import { DocumentReview } from "./document-review.js";
import {
  DocumentError,
  checkDocxBibliographyEdit,
  type DocxBibliographyEdit,
} from "../core/foundation.js";
import {
  checkDocxCitationEdit,
  checkDocxSourceEdit,
  type DocxSource,
  type DocxSourceEdit,
  type DocxSources,
} from "../core/foundation.js";
export type DocumentSources = DocxSources & { documentId: string };

export abstract class DocumentSourcesEditor extends DocumentReview {
  protected abstract readonly profile: Record<string, string>;
  insertBibliography(source: DocumentSources, title: string): Promise<void> {
    const change = { action: "insert", title } as const;
    checkDocxBibliographyEdit(change);
    return this.review.edit(() => {
      const current = this.review.snapshot();
      if (
        source.documentId !== current.documentId ||
        source.revision !== current.revision
      )
        throw new DocumentError(
          "stale-sources",
          "Select a current source catalog",
          "",
          -1,
        );
      return this.review.client.editBibliography(
        source.revision,
        change,
        this.profile,
      );
    });
  }
  editBibliography(
    source: DocumentSources,
    change: Extract<DocxBibliographyEdit, { action: "update" | "delete" }>,
  ): Promise<void> {
    checkDocxBibliographyEdit(change);
    return this.review.edit(() => {
      const current = this.review.snapshot(),
        item = source.bibliographies.find(
          (item) => item.paragraph === change.paragraph,
        );
      if (
        source.documentId !== current.documentId ||
        source.revision !== current.revision ||
        !item ||
        item.reason
      )
        throw new DocumentError(
          "stale-sources",
          item?.reason || "Bibliography catalog is stale",
          "",
          -1,
        );
      return this.review.client.editBibliography(
        source.revision,
        change,
        this.profile,
      );
    });
  }
  insertCitation(source: DocumentSources, tag: string): Promise<void> {
    const change = { action: "insert", tag } as const;
    checkDocxCitationEdit(change);
    return this.review.edit(() => {
      const current = this.review.snapshot();
      const entry = source.sources.find((item) => item.tag === tag);
      if (
        source.documentId !== current.documentId ||
        source.revision !== current.revision ||
        !entry ||
        entry.reason ||
        entry.authorReason ||
        !(entry.author || entry.title)
      )
        throw new DocumentError(
          "stale-sources",
          entry?.reason || entry?.authorReason || "Source catalog is stale",
          "",
          -1,
        );
      return this.review.client.editCitation(
        source.revision,
        change,
        this.profile,
      );
    });
  }
  updateCitations(): Promise<void> {
    return this.review.edit(() =>
      this.review.client.editCitation(
        this.review.snapshot().revision,
        { action: "update" },
        this.profile,
      ),
    );
  }
  sources(): Promise<DocumentSources> {
    return this.review.read(async () => ({
      ...(await this.review.client.sources(this.review.snapshot().revision)),
      documentId: this.review.snapshot().documentId,
    }));
  }
  createSource(source: DocxSource): Promise<void> {
    const change = { action: "create", source } as const;
    checkDocxSourceEdit(change);
    return this.review.edit(async () => {
      const revision = this.review.snapshot().revision;
      const catalog = await this.review.client.sources(revision);
      if (catalog.sources.some((entry) => entry.tag === source.tag))
        throw new DocumentError(
          "stale-sources",
          "Source tag already exists",
          "",
          -1,
        );
      return this.review.client.editSource(revision, change);
    });
  }
  editSource(source: DocumentSources, change: DocxSourceEdit): Promise<void> {
    checkDocxSourceEdit(change);
    return this.review.edit(() => {
      const current = this.review.snapshot();
      const tag = change.action === "delete" ? change.tag : change.source.tag;
      const item = source.sources.find((entry) => entry.tag === tag);
      if (
        change.action === "create" ||
        source.documentId !== current.documentId ||
        source.revision !== current.revision ||
        !item ||
        item.reason ||
        (change.action === "update" &&
          item.authorReason &&
          item.author !== change.source.author) ||
        (change.action === "delete" && item.deleteReason)
      )
        throw new DocumentError(
          "stale-sources",
          item?.reason ||
            item?.authorReason ||
            item?.deleteReason ||
            "Source catalog is stale",
          "",
          -1,
        );
      return this.review.client.editSource(source.revision, change);
    });
  }
}
