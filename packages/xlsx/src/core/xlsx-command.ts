import { xlsxSheetCommands } from "./xlsx-command-sheet.js";
import { xlsxDrawingCommands } from "./xlsx-command-drawing.js";
import { xlsxCommentCommands } from "./xlsx-command-comment.js";
import {
  expandXlsxViewport,
  type CompactXlsxViewport,
  type XlsxViewport,
} from "./xlsx-grid.js";

export const xlsxCommands = {
  ...xlsxSheetCommands,
  ...xlsxDrawingCommands,
  ...xlsxCommentCommands,
};

export type XlsxCommand = {
  [Operation in keyof typeof xlsxCommands]: {
    operation: Operation;
  } & Parameters<(typeof xlsxCommands)[Operation]>[1];
}[keyof typeof xlsxCommands];

export type XlsxResult<C extends XlsxCommand> = C extends {
  operation: "viewportXlsx";
}
  ? XlsxViewport
  : ReturnType<(typeof xlsxCommands)[C["operation"]]>;

export function decodeXlsxResult<C extends XlsxCommand>(
  command: C,
  result: unknown,
): XlsxResult<C> {
  return (
    command.operation === "viewportXlsx"
      ? expandXlsxViewport(result as CompactXlsxViewport)
      : result
  ) as XlsxResult<C>;
}
