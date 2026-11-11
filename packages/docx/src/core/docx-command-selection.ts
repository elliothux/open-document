import { type EditState } from "./docx-format.js";
import { type DocxSelection, type DocxSelectionGeometry } from "./docx-hit.js";
import type { DocxRuntime } from "./docx-session.js";
export const docxSelectionCommands = {
  selectDocx(
    session: DocxRuntime,
    { revision, selection }: { revision: number; selection: DocxSelection },
  ): EditState {
    return session.call<EditState>({
      operation: "selectDocx",
      revision,
      selection,
    });
  },
  selectAllDocx(
    session: DocxRuntime,
    { revision }: { revision: number },
  ): EditState {
    return session.call<EditState>({ operation: "selectAllDocx", revision });
  },
  selectionGeometry(
    session: DocxRuntime,
    { layoutId, selection }: { layoutId: number; selection: DocxSelection },
  ): DocxSelectionGeometry {
    return session.call<DocxSelectionGeometry>({
      operation: "selectionGeometry",
      layoutId,
      selection,
    });
  },
};
