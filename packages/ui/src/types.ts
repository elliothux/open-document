import type { ReactNode } from "react";
import type { EngineHandle } from "@open-document/wasm";
import type {
  EditorOutput,
  EditorSnapshot,
  EditorFormat,
} from "@open-document/web-core/editor-state";
import type { EditorController, UiSnapshot } from "./controller.js";
import type { MessageKey } from "./messages.js";

export type Locale = "en-US" | "zh-CN";
export type Theme = "light" | "dark";
export interface DelimitedOptions {
  numbers?: boolean;
  dates?: boolean;
  formulas?: boolean;
}
export interface EditorDocument {
  readonly name: string;
  readonly bytes: Uint8Array;
  readonly blank?: never;
  readonly delimited?: DelimitedOptions;
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
  readonly engine: EngineHandle;
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
export interface CommonOptions {
  readonly resources: EditorResources;
  readonly theme?: Theme;
  readonly locale?: Locale;
  readonly onSave?: (document: SavedDocument) => Promise<void> | void;
  readonly onOpen?: () => Promise<void> | void;
  readonly signal?: AbortSignal;
  readonly styleNonce?: string;
  readonly commentAuthor?: { name: string; initials: string };
}
/** Internal shell options; each domain owns its public options and budget. */
export interface EditorOptions extends CommonOptions {
  readonly document: OfficeDocument;
}
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
  open(document: OfficeDocument): Promise<boolean>;
  save(): Promise<SavedDocument>;
  saveAs(name: string): Promise<SavedDocument>;
  print(): Promise<void>;
  close(): Promise<boolean>;
  dispose(): Promise<void>;
  setTheme(theme: Theme): void;
  setLocale(locale: Locale): void;
}
export interface EditorHost {
  getSnapshot(): EditorSnapshot;
  subscribe(listener: () => void): () => void;
  setPaused(paused: boolean): Promise<void>;
  setZoom(zoom: number): Promise<void>;
  undo(): Promise<unknown>;
  redo(): Promise<unknown>;
  copy(): Promise<void>;
  focus(): void;
  markSaved(output: EditorOutput): void;
  markDownloaded(output: EditorOutput): void;
  dispose(): Promise<void>;
}
export interface ClipboardActions {
  readonly canCopy: boolean;
  readonly textMode: boolean;
  readonly readOnly: boolean;
  readonly richText?: boolean;
  cut?(): Promise<void>;
  paste?(
    text: string,
    format: string,
    mode: "source" | "merge" | "text",
  ): Promise<void>;
  pasteClipboard?(): Promise<unknown>;
}
export interface OwnedFile<E extends EditorHost = EditorHost> {
  readonly format: EditorFormat;
  readonly editor: E;
  readonly surface: HTMLElement;
  readonly inputLimit: number;
  readonly originalName: string;
  readonly imported: boolean;
  readonly draftCanSave: boolean;
  cancelDraft?(): void;
  navigate(index: number): Promise<void> | undefined;
  recover(): Promise<void>;
  output(kind: string): Promise<EditorOutput>;
  pageImages?(format: "png" | "jpeg"): Promise<readonly EditorOutput[]>;
  clipboard(): ClipboardActions;
  dispose(): Promise<void>;
}
export interface PanelProps<E extends EditorHost = EditorHost> {
  controller: EditorController<E>;
  state: UiSnapshot<E>;
  file: OwnedFile<E>;
  disabled: boolean;
}
export type PanelSlot =
  | "edit"
  | "view"
  | "pages"
  | "annotations"
  | "navigation"
  | "pages-list"
  | "properties"
  | "before-surface"
  | "after-surface"
  | "status";
export interface Product<E extends EditorHost> {
  readonly format: EditorFormat;
  readonly canCreate: boolean;
  readonly delimited: boolean;
  readonly accept: string;
  readonly readLabel: boolean;
  readonly extraTabs: boolean;
  readonly addressStatus: boolean;
  readonly editReadOnly: boolean;
  readonly outputs: readonly {
    kind: string;
    label: MessageKey;
    title?: MessageKey;
  }[];
  prepare(
    document: OfficeDocument,
    parent: HTMLElement,
    signal: AbortSignal,
  ): Promise<OwnedFile<E>>;
  render(slot: PanelSlot, props: PanelProps<E>): ReactNode;
}
export const mime: Record<EditorOutput["format"], string> = {
  png: "image/png",
  jpeg: "image/jpeg",
  csv: "text/csv;charset=utf-8",
  html: "text/html;charset=utf-8",
  markdown: "text/markdown;charset=utf-8",
  docx: "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
  xlsx: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
  pptx: "application/vnd.openxmlformats-officedocument.presentationml.presentation",
  pdf: "application/pdf",
};
