import type { PdfEditor } from "../web/index.js";
import type {
  CommonOptions,
  MountedProduct,
  OfficeDocument,
} from "@open-document/ui/types";
import type { PdfBudget } from "../core/index.js";
export type {
  CommonOptions,
  EditorResources,
  EditorDocument,
  OfficeDocument,
  MountedSnapshot,
  SavedDocument,
  Locale,
  Theme,
  EditorMode,
  EditorSlots,
} from "@open-document/ui/types";
export interface EditorOptions extends CommonOptions {
  readonly document: OfficeDocument | File;
  readonly budget?: PdfBudget;
  readonly fileBudget?: PdfBudget;
}
export type MountedEditor = MountedProduct<PdfEditor, "pdf">;
