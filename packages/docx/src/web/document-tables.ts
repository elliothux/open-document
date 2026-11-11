import type { DocumentHost } from "./document-host.js";
import type { FoundationClient } from "./foundation.js";
import type { DocxTableEdit } from "../core/foundation.js";

/** Table commands retain the editor's existing source transaction and queue. */
export function createDocumentTables(
  client: FoundationClient,
  profile: Record<string, string>,
  host: DocumentHost,
) {
  return {
    insertTable(rows: number, cols: number): Promise<void> {
      return host.edit(() =>
        client.execute({
          operation: "insertTable",
          revision: host.snapshot().revision,
          selection: host.selection(),
          rows: rows,
          columns: cols,
          profile: profile,
        }),
      );
    },
    editTable(change: DocxTableEdit): Promise<void> {
      return host.edit(() => {
        return client.execute({
          operation: "editTable",
          revision: host.snapshot().revision,
          selection: host.selection(),
          change,
          profile: profile,
        });
      });
    },
  };
}
