import type { PresentationEditor } from "../web/index.js";
import type {
  EditorController as Controller,
  UiSnapshot as Snapshot,
} from "@open-document/ui/controller";
import type {
  OwnedFile as File,
  PanelProps as Props,
} from "@open-document/ui/types";
export type EditorController = Controller<PresentationEditor>;
export type UiSnapshot = Snapshot<PresentationEditor>;
export type OwnedFile = File<PresentationEditor>;
export type PanelProps = Props<PresentationEditor>;
