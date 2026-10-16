import type { DocumentEditor } from "@open-document/web/editor";
import type { SpreadsheetEditor } from "@open-document/web/spreadsheet-editor";
import type { PresentationEditor } from "@open-document/web/presentation-editor";
import type { PdfEditor } from "@open-document/web/pdf-editor";
import type { FoundationClient } from "@open-document/web/foundation";
import type { PdfClient } from "@open-document/web/pdf";
import type { XlsxDelimitedOptions } from "@open-document/web/xlsx";
import type {
  EditorOutput,
  EditorSnapshot,
} from "@open-document/web/editor-state";

export type Locale = "en-US" | "zh-CN";
export type Theme = "light" | "dark";
export interface EditorDocument {
  readonly name: string;
  readonly bytes: Uint8Array;
  readonly blank?: never;
  /** Explicit conversions for CSV/TSV input in an XLSX editor. */
  readonly delimited?: XlsxDelimitedOptions;
}
export type OfficeDocument =
  | EditorDocument
  | {
      readonly name: string;
      readonly blank: true;
      readonly bytes?: never;
      readonly delimited?: never;
    };
export interface EditorResources {
  readonly wasm: ArrayBuffer;
  readonly workerUrl: URL;
  readonly fonts: readonly {
    readonly identity: string;
    readonly bytes: Uint8Array;
  }[];
  readonly profile: Readonly<Record<string, string>>;
}
export interface SavedDocument extends EditorOutput {
  readonly name: string;
}
interface CommonOptions {
  readonly resources: EditorResources;
  readonly theme?: Theme;
  readonly locale?: Locale;
  readonly onSave?: (document: SavedDocument) => Promise<void> | void;
  readonly signal?: AbortSignal;
  readonly styleNonce?: string;
}
type OfficeBudget = Awaited<ReturnType<FoundationClient["defaultBudget"]>>;
type PdfBudget = Awaited<ReturnType<PdfClient["defaultBudget"]>>;
export type EditorOptions = CommonOptions &
  (
    | {
        readonly budget?: OfficeBudget;
        readonly format: "docx" | "xlsx" | "pptx";
        readonly document: OfficeDocument;
      }
    | {
        readonly format: "pdf";
        readonly document: EditorDocument;
        readonly budget?: PdfBudget;
      }
  );
export type MountedSnapshot = EditorSnapshot & {
  readonly name: string;
  readonly saving: boolean;
  readonly loading: boolean;
  readonly message: string;
  readonly newDocument: boolean;
};
export interface MountedMethods {
  getSnapshot(): MountedSnapshot;
  subscribe(listener: () => void): () => void;
  open(document: EditorDocument): Promise<boolean>;
  save(): Promise<SavedDocument>;
  saveAs(name: string): Promise<SavedDocument>;
  close(): Promise<boolean>;
  dispose(): Promise<void>;
  setTheme(theme: Theme): void;
  setLocale(locale: Locale): void;
}
export type MountedEditor = MountedMethods &
  (
    | ({
        create(document: { readonly name: string }): Promise<boolean>;
        open(document: OfficeDocument): Promise<boolean>;
      } & (
        | { readonly format: "docx"; readonly editor: DocumentEditor }
        | { readonly format: "xlsx"; readonly editor: SpreadsheetEditor }
        | { readonly format: "pptx"; readonly editor: PresentationEditor }
      ))
    | { readonly format: "pdf"; readonly editor: PdfEditor }
  );
export type EditorFile =
  | { readonly format: "docx"; readonly editor: DocumentEditor }
  | { readonly format: "xlsx"; readonly editor: SpreadsheetEditor }
  | { readonly format: "pptx"; readonly editor: PresentationEditor }
  | { readonly format: "pdf"; readonly editor: PdfEditor };
export type OwnedFile = EditorFile & {
  readonly surface: HTMLElement;
  readonly inputLimit: number;
  dispose(): Promise<void>;
};
export const mime: Record<EditorOutput["format"], string> = {
  csv: "text/csv;charset=utf-8",
  docx: "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
  xlsx: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
  pptx: "application/vnd.openxmlformats-officedocument.presentationml.presentation",
  pdf: "application/pdf",
};
