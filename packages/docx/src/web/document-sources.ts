import type { DocumentHost } from "./document-host.js";
import type { FoundationClient } from "./foundation.js";
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

export function createDocumentSources(
  client: FoundationClient,
  profile: Record<string, string>,
  host: DocumentHost,
) {
  return {
    insertBibliography(source: DocumentSources, title: string): Promise<void> {
      const change = { action: "insert", title } as const;
      checkDocxBibliographyEdit(change);
      return host.edit(() => {
        const current = host.snapshot();
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
        return client.execute({
          operation: "editBibliography",
          revision: source.revision,
          change: change,
          profile: profile,
        });
      });
    },
    editBibliography(
      source: DocumentSources,
      change: Extract<DocxBibliographyEdit, { action: "update" | "delete" }>,
    ): Promise<void> {
      checkDocxBibliographyEdit(change);
      return host.edit(() => {
        const current = host.snapshot(),
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
        return client.execute({
          operation: "editBibliography",
          revision: source.revision,
          change: change,
          profile: profile,
        });
      });
    },
    insertCitation(source: DocumentSources, tag: string): Promise<void> {
      const change = { action: "insert", tag } as const;
      checkDocxCitationEdit(change);
      return host.edit(() => {
        const current = host.snapshot();
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
        return client.execute({
          operation: "editCitation",
          revision: source.revision,
          change: change,
          profile: profile,
        });
      });
    },
    updateCitations(): Promise<void> {
      return host.edit(() =>
        client.execute({
          operation: "editCitation",
          revision: host.snapshot().revision,
          change: { action: "update" },
          profile: profile,
        }),
      );
    },
    catalog(): Promise<DocumentSources> {
      return host.read(async () => ({
        ...(await client.execute({
          operation: "sources",
          revision: host.snapshot().revision,
        })),
        documentId: host.snapshot().documentId,
      }));
    },
    createSource(source: DocxSource): Promise<void> {
      const change = { action: "create", source } as const;
      checkDocxSourceEdit(change);
      return host.edit(async () => {
        const revision = host.snapshot().revision;
        const catalog = await client.execute({
          operation: "sources",
          revision: revision,
        });
        if (catalog.sources.some((entry) => entry.tag === source.tag))
          throw new DocumentError(
            "stale-sources",
            "Source tag already exists",
            "",
            -1,
          );
        return client.execute({
          operation: "editSource",
          revision: revision,
          change: change,
        });
      });
    },
    editSource(source: DocumentSources, change: DocxSourceEdit): Promise<void> {
      checkDocxSourceEdit(change);
      return host.edit(() => {
        const current = host.snapshot();
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
        return client.execute({
          operation: "editSource",
          revision: source.revision,
          change: change,
        });
      });
    },
  };
}
