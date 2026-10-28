import type { DocumentEditor } from "../web/index.js";
import type {
  EditorController as Controller,
  UiSnapshot as Snapshot,
} from "@open-document/ui/controller";
import type {
  OwnedFile as File,
  PanelProps as Props,
} from "@open-document/ui/types";
export type EditorController = Controller<DocumentEditor>;
export type UiSnapshot = Snapshot<DocumentEditor>;
export type OwnedFile = File<DocumentEditor>;
export type PanelProps = Props<DocumentEditor>;
