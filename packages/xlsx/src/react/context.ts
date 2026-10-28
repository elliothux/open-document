import type { SpreadsheetEditor } from "../web/index.js";
import type {
  EditorController as Controller,
  UiSnapshot as Snapshot,
} from "@open-document/ui/controller";
import type {
  OwnedFile as File,
  PanelProps as Props,
} from "@open-document/ui/types";
export type EditorController = Controller<SpreadsheetEditor>;
export type UiSnapshot = Snapshot<SpreadsheetEditor>;
export type OwnedFile = File<SpreadsheetEditor>;
export type PanelProps = Props<SpreadsheetEditor>;
