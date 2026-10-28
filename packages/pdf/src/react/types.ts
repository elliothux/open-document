import type { PdfEditor } from "../web/index.js";
import type {
  CommonOptions,
  MountedMethods,
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
} from "@open-document/ui/types";
export interface EditorOptions extends CommonOptions {
  readonly document: OfficeDocument;
  readonly budget?: PdfBudget;
}
export type MountedEditor = MountedMethods & {
  create(document: { readonly name: string }): Promise<boolean>;
  readonly format: "pdf";
  readonly editor: PdfEditor;
};
