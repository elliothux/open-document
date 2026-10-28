import type { PdfEditor } from "../web/index.js";
import type {
  EditorController as Controller,
  UiSnapshot as Snapshot,
} from "@open-document/ui/controller";
import type {
  OwnedFile as File,
  PanelProps as Props,
} from "@open-document/ui/types";
export type EditorController = Controller<PdfEditor>;
export type UiSnapshot = Snapshot<PdfEditor>;
export type OwnedFile = File<PdfEditor>;
export type PanelProps = Props<PdfEditor>;
