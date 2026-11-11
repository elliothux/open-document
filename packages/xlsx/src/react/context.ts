import type { SpreadsheetEditor } from "../web/index.js";
import type { MouseEvent } from "react";
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

export function preserveGridDraft(event: MouseEvent) {
  // The queued action commits the draft before changing the selection.
  if (
    event.button === 0 &&
    event.target instanceof Element &&
    event.target.closest("button")
  )
    event.preventDefault();
}
