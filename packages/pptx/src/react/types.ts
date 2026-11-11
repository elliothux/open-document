import type { PresentationEditor } from "../web/index.js";
import type {
  CommonOptions,
  MountedProduct,
  OfficeDocument,
} from "@open-document/ui/types";
import type { Budget } from "@open-document/wasm/abi/validation";
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
  readonly document: OfficeDocument;
  readonly budget?: Budget;
}
export type MountedEditor = MountedProduct<PresentationEditor, "pptx">;
