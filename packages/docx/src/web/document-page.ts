import type { DocumentHost } from "./document-host.js";
import type { FoundationClient } from "./foundation.js";
import { verifyEncodedImage } from "@open-document/web-core/image";
import { DocumentError } from "../core/foundation.js";
import type {
  DocxTocEdit,
  DocxTableOfContents,
  DocxIndexes,
  DocxIndexEdit,
  DocxWatermark,
  DocxSectionBreak,
  DocxRuler,
  DocxRulerEdit,
  DocxPageSetup,
  DocxPageBorders,
  DocxPageNumbering,
  DocxColumns,
  DocxRunningKind,
  DocxCoverPage,
  DocxCaption,
  DocxRunningVariant,
  DocxRunningContent,
  DocxBodyField,
  DocxBodyPageField,
  DocxProtection,
} from "../core/foundation.js";
export type DocumentTableOfContents = DocxTableOfContents & {
  documentId: string;
};
export type DocumentIndexes = DocxIndexes & { documentId: string };
export type DocumentRuler = DocxRuler & { documentId: string };
export type DocumentBodyPageField = DocxBodyPageField & { documentId: string };
export type DocumentProtection = DocxProtection & { documentId: string };
export function createDocumentPages(
  client: FoundationClient,
  profile: Record<string, string>,
  host: DocumentHost,
) {
  return {
    indexes(): Promise<DocumentIndexes> {
      return host.read(async () => ({
        ...(await client.execute({
          operation: "indexes",
          revision: host.snapshot().revision,
        })),
        documentId: host.snapshot().documentId,
      }));
    },
    markIndexEntry(label: string): Promise<void> {
      return host.edit(() =>
        client.execute({
          operation: "editIndex",
          revision: host.snapshot().revision,
          change: { action: "mark", label },
          profile: profile,
        }),
      );
    },
    insertIndex(): Promise<void> {
      return host.edit(() =>
        client.execute({
          operation: "editIndex",
          revision: host.snapshot().revision,
          change: { action: "insert" },
          profile: profile,
        }),
      );
    },
    editIndex(
      source: DocumentIndexes,
      change: Exclude<DocxIndexEdit, { action: "mark" | "insert" }>,
    ): Promise<void> {
      return host.edit(() => {
        const current = host.snapshot();
        const item =
          "id" in change
            ? source.entries.find((item) => item.id === change.id)
            : source.indexes.find(
                (item) => item.paragraph === change.paragraph,
              );
        if (
          source.documentId !== current.documentId ||
          source.revision !== current.revision ||
          !item ||
          item.reason
        )
          throw new DocumentError(
            "stale-index",
            item?.reason || "Index catalog is stale",
            "",
            -1,
          );
        return client.execute({
          operation: "editIndex",
          revision: source.revision,
          change: change,
          profile: profile,
        });
      });
    },
    insertSectionBreak(kind: DocxSectionBreak): Promise<void> {
      return host.edit(() =>
        client.execute({
          operation: "insertSectionBreak",
          revision: host.snapshot().revision,
          kind: kind,
          profile: profile,
        }),
      );
    },
    tableOfContents(): Promise<DocumentTableOfContents> {
      return host.read(async () => ({
        ...(await client.execute({
          operation: "tableOfContents",
          revision: host.snapshot().revision,
        })),
        documentId: host.snapshot().documentId,
      }));
    },
    insertTableOfContents(levels = 3): Promise<void> {
      return host.edit(() =>
        client.execute({
          operation: "editTableOfContents",
          revision: host.snapshot().revision,
          change: { action: "insert", levels },
          profile: profile,
        }),
      );
    },
    insertTableOfFigures(sequence: string): Promise<void> {
      return host.edit(() =>
        client.execute({
          operation: "editTableOfContents",
          revision: host.snapshot().revision,
          change: { action: "insertCaptions", sequence },
          profile: profile,
        }),
      );
    },
    editTableOfContents(
      source: DocumentTableOfContents,
      change: Extract<DocxTocEdit, { action: "update" | "delete" }>,
    ): Promise<void> {
      return host.edit(() => {
        const current = host.snapshot(),
          item = source.items.find(
            (item) => item.paragraph === change.paragraph,
          );
        if (
          source.documentId !== current.documentId ||
          source.revision !== current.revision ||
          !item ||
          item.reason
        )
          throw new DocumentError(
            "stale-toc",
            item?.reason || "Table of contents catalog is stale",
            "",
            -1,
          );
        return client.execute({
          operation: "editTableOfContents",
          revision: source.revision,
          change: change,
          profile: profile,
        });
      });
    },
    documentProtection(): Promise<DocumentProtection> {
      return host.read(async () => ({
        ...(await client.execute({
          operation: "documentProtection",
          revision: host.snapshot().revision,
        })),
        documentId: host.snapshot().documentId,
      }));
    },
    setDocumentProtection(
      source: DocumentProtection,
      enabled: boolean,
      password = "",
    ): Promise<void> {
      return host.edit(() => {
        const current = host.snapshot();
        if (
          source.documentId !== current.documentId ||
          source.revision !== current.revision
        )
          throw new Error("Document protection state is stale");
        return client.execute({
          operation: "setDocumentProtection",
          revision: source.revision,
          enabled: enabled,
          password: password,
        });
      });
    },
    bodyPageField(): Promise<DocumentBodyPageField> {
      return host.read(async () => {
        const state = host.snapshot();
        return {
          ...(await client.execute({
            operation: "bodyPageField",
            revision: state.revision,
            selection: host.selection(),
          })),
          documentId: state.documentId,
        };
      });
    },
    editBodyPageField(
      source: DocumentBodyPageField,
      field: DocxBodyField,
    ): Promise<void> {
      return host.edit(() => {
        const current = host.snapshot();
        if (
          source.documentId !== current.documentId ||
          source.revision !== current.revision ||
          JSON.stringify(source.selection) !== JSON.stringify(host.selection())
        )
          throw new Error("Document or field selection changed");
        return client.execute({
          operation: "editBodyPageField",
          revision: source.revision,
          selection: source.selection,
          field: field,
          profile: profile,
        });
      });
    },
    insertBodyPageField(field: DocxBodyField): Promise<void> {
      return host.edit(() =>
        client.execute({
          operation: "insertBodyPageField",
          revision: host.snapshot().revision,
          field: field,
          profile: profile,
        }),
      );
    },
    insertCaption(caption: DocxCaption): Promise<void> {
      return host.edit(() =>
        client.execute({
          operation: "insertCaption",
          revision: host.snapshot().revision,
          caption: caption,
          profile: profile,
        }),
      );
    },
    updateBodyPageFields(): Promise<void> {
      return host.edit(() =>
        client.execute({
          operation: "updateBodyPageFields",
          revision: host.snapshot().revision,
          profile: profile,
        }),
      );
    },
    ruler(): Promise<DocumentRuler> {
      return host.read(async () => ({
        ...(await client.execute({
          operation: "ruler",
          revision: host.snapshot().revision,
        })),
        documentId: host.snapshot().documentId,
      }));
    },
    editRuler(source: DocumentRuler, change: DocxRulerEdit): Promise<void> {
      return host.edit(() => {
        if (source.documentId !== host.snapshot().documentId)
          throw new Error("Ruler belongs to another document");
        return client.execute({
          operation: "editRuler",
          source: source,
          change: change,
        });
      });
    },
    setPageColumns(
      section: number,
      columns: DocxColumns | null,
    ): Promise<void> {
      return host.edit(() =>
        client.execute({
          operation: "setPageColumns",
          revision: host.snapshot().revision,
          section: section,
          columns: columns,
          profile: profile,
        }),
      );
    },
    setPageNumbering(
      section: number,
      numbering: DocxPageNumbering | null,
    ): Promise<void> {
      return host.edit(() =>
        client.execute({
          operation: "setPageNumbering",
          revision: host.snapshot().revision,
          section: section,
          numbering: numbering,
          profile: profile,
        }),
      );
    },
    setRunningLink(
      section: number,
      kind: DocxRunningKind,
      variant: DocxRunningVariant,
      linked: boolean,
    ): Promise<void> {
      return host.edit(() =>
        client.execute({
          operation: "setRunningLink",
          revision: host.snapshot().revision,
          section: section,
          kind: kind,
          variant: variant,
          linked: linked,
          profile: profile,
        }),
      );
    },
    runningArea(
      section: number,
      kind: DocxRunningKind,
      variant: DocxRunningVariant,
    ) {
      return host.read(() =>
        client.execute({
          operation: "runningArea",
          revision: host.snapshot().revision,
          section: section,
          kind: kind,
          variant: variant,
        }),
      );
    },
    setRunningArea(
      section: number,
      kind: DocxRunningKind,
      variant: DocxRunningVariant,
      content: DocxRunningContent[],
      distance: number,
    ): Promise<void> {
      return host.edit(() =>
        client.execute({
          operation: "setRunningArea",
          revision: host.snapshot().revision,
          section: section,
          kind: kind,
          variant: variant,
          content: content,
          distance: distance,
          profile: profile,
        }),
      );
    },
    setPageBorders(
      section: number,
      borders: DocxPageBorders | null,
    ): Promise<void> {
      return host.edit(() =>
        client.execute({
          operation: "setPageBorders",
          revision: host.snapshot().revision,
          section: section,
          borders: borders,
        }),
      );
    },
    setRunningOptions(
      section: number,
      first: boolean,
      even: boolean,
    ): Promise<void> {
      return host.edit(() =>
        client.execute({
          operation: "setRunningOptions",
          revision: host.snapshot().revision,
          section: section,
          first: first,
          even: even,
          profile: profile,
        }),
      );
    },
    pageSetup(section = 0) {
      return host.read(() =>
        client.execute({
          operation: "pageSetup",
          revision: host.snapshot().revision,
          section: section,
        }),
      );
    },
    setPageSetup(page: DocxPageSetup): Promise<void> {
      return host.edit(() =>
        client.execute({
          operation: "setPageSetup",
          revision: host.snapshot().revision,
          page: page,
        }),
      );
    },
    setPageBackground(color: string | null): Promise<void> {
      return host.edit(() =>
        client.execute({
          operation: "setPageBackground",
          revision: host.snapshot().revision,
          color: color,
        }),
      );
    },
    watermark(section: number) {
      return host.read(async () => {
        const current = host.snapshot();
        return {
          ...(await client.execute({
            operation: "watermark",
            revision: current.revision,
            section: section,
          })),
          documentId: current.documentId,
        };
      });
    },
    imageDimensions(bytes: Uint8Array) {
      return host.read(async () => {
        const header = await client.execute({
          operation: "rasterHeaderDocx",
          bytes,
        });
        if ("error" in header) throw new Error(header.error);
        return header;
      });
    },
    setWatermark(section: number, value: DocxWatermark | null): Promise<void> {
      return host.edit(async () => {
        const current = host.snapshot();
        const prepared =
          value?.kind === "picture" && value.image instanceof Uint8Array
            ? { ...value, image: value.image.slice() }
            : value;
        if (
          prepared?.kind === "picture" &&
          prepared.image instanceof Uint8Array
        ) {
          const header = await client.execute({
            operation: "rasterHeaderDocx",
            bytes: prepared.image,
            verify: true,
          });
          await verifyEncodedImage(prepared.image, header);
          if (
            host.snapshot().documentId !== current.documentId ||
            host.snapshot().revision !== current.revision
          )
            throw new Error(
              "Watermark source changed during image preparation",
            );
        }
        return client.execute({
          operation: "setWatermark",
          revision: current.revision,
          section: section,
          value: prepared,
          profile: profile,
        });
      });
    },
    setCoverPage(cover: DocxCoverPage | null): Promise<void> {
      return host.edit(() =>
        client.execute({
          operation: "setCoverPage",
          revision: host.snapshot().revision,
          cover: cover,
          profile: profile,
        }),
      );
    },
  };
}
