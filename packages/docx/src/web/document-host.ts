import type { EditState, DocxSelection } from "../core/foundation.js";
import type { PageLayout } from "../core/preview.js";
import type { EditorSnapshot } from "@open-document/web-core/editor-state";

/** Domain operations share the editor's live state and transaction barriers. */
export interface DocumentHost {
  read<T>(operation: () => Promise<T>): Promise<T>;
  edit(operation: () => Promise<EditState>): Promise<void>;
  snapshot(): EditorSnapshot;
  layout(): PageLayout;
  selection(): DocxSelection;
}
