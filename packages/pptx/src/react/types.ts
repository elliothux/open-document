import type { PresentationEditor } from "../web/index.js";
import type {
  CommonOptions,
  MountedMethods,
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
} from "@open-document/ui/types";
export interface EditorOptions extends CommonOptions {
  readonly document: OfficeDocument;
  readonly budget?: Budget;
}
export type MountedEditor = MountedMethods & {
  readonly format: "pptx";
  readonly editor: PresentationEditor;
  create(document: { readonly name: string }): Promise<boolean>;
};
