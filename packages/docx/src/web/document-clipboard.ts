import type { DocumentHost } from "./document-host.js";
import type { FoundationClient } from "./foundation.js";
import { DOCX_SOFT_BREAK } from "../core/foundation.js";
import type { DocxPasteMode } from "../core/foundation.js";
/** Rich text uses the existing edit queue and core-owned resource transaction. */
export function createDocumentClipboard(
  client: FoundationClient,
  profile: Record<string, string>,
  host: DocumentHost & { paste(text: string): Promise<void> },
) {
  return {
    /** Selects the body, or the text box containing the current caret. */
    selectAll(): Promise<void> {
      return host.edit(() =>
        client.execute({
          operation: "selectAllDocx",
          revision: host.snapshot().revision,
        }),
      );
    },
    insertSoftBreak(): Promise<void> {
      return host.paste(DOCX_SOFT_BREAK);
    },
    pasteHtml(html: string, mode: DocxPasteMode = "source"): Promise<void> {
      return host.edit(() => {
        const state = host.snapshot();
        return client.execute({
          operation: "pasteHtml",
          revision: state.revision,
          selection: host.selection(),
          html: html,
          profile: profile,
          mode: mode,
        });
      });
    },
    pasteMarkdown(
      markdown: string,
      mode: DocxPasteMode = "source",
    ): Promise<void> {
      return host.edit(() => {
        const state = host.snapshot();
        return client.execute({
          operation: "pasteMarkdown",
          revision: state.revision,
          selection: host.selection(),
          markdown: markdown,
          profile: profile,
          mode: mode,
        });
      });
    },
    pasteFragment(fragment: string): Promise<void> {
      return host.edit(() => {
        const state = host.snapshot();
        return client.execute({
          operation: "pasteBodyFragment",
          revision: state.revision,
          selection: host.selection(),
          fragment: fragment,
          profile: profile,
        });
      });
    },
  };
}
