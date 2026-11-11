import type { SpreadsheetHost } from "./spreadsheet-host.js";
import type { XlsxClient } from "./xlsx.js";
import type { SpreadsheetCanvas } from "./spreadsheet-canvas.js";
import type { XlsxPasteMode } from "../core/xlsx.js";
import {
  copyCellData,
  copySpreadsheetDrawing,
  pasteSpreadsheetCells,
  cutSpreadsheetDrawing,
  pasteSpreadsheetDrawing,
} from "./spreadsheet-clipboard.js";

/** Clipboard access uses the editor's draft barrier, queue and disposal checks. */
export function createSpreadsheetClipboard(
  client: XlsxClient,
  profile: Record<string, string>,
  surface: SpreadsheetCanvas,
  host: SpreadsheetHost & {
    closed(): boolean;
    selectedDrawing(): string | undefined;
    acceptWarnings(): boolean;
  },
) {
  return {
    paste(text: string): Promise<void> {
      return host.change(() =>
        client.execute({
          operation: "pasteXlsx",
          revision: host.state().revision,
          text: text,
          acceptWarnings: host.acceptWarnings(),
        }),
      );
    },
    copyCells(cut = false): Promise<void> {
      return host.read(() => copyCellData(client, host.state(), true, cut));
    },
    pasteCells(mode: XlsxPasteMode = "all", transpose = false): Promise<void> {
      return host.change(() =>
        pasteSpreadsheetCells(
          client,
          host.state(),
          profile,
          mode,
          transpose,
          host.acceptWarnings(),
          () => host.closed(),
        ),
      );
    },
    copy(): Promise<void> {
      return host.read(() => {
        const drawing = host.selectedDrawing();
        return drawing
          ? copySpreadsheetDrawing(client, host.state(), drawing, profile)
          : copyCellData(client, host.state(), false);
      });
    },
    copyDrawing(id: string): Promise<void> {
      return host.read(() =>
        copySpreadsheetDrawing(client, host.state(), id, profile),
      );
    },
    cutSelection(): Promise<void> {
      return host.read(() => {
        const drawing = host.selectedDrawing();
        return drawing
          ? cutSpreadsheetDrawing(client, host.state(), drawing)
          : copyCellData(client, host.state(), true, true);
      });
    },
    cutDrawing(id: string): Promise<void> {
      return host.read(() => cutSpreadsheetDrawing(client, host.state(), id));
    },
    pasteDrawing(): Promise<void> {
      return host.change(() =>
        pasteSpreadsheetDrawing(
          client,
          host.state(),
          profile,
          () => host.closed(),
          async (fragment) => {
            const bytes = await client.execute({
              operation: "drawingFragmentImageXlsx",
              revision: host.state().revision,
              fragment: fragment,
            });
            if (bytes)
              await surface.addPicture(client, host.state().revision, bytes);
          },
        ),
      );
    },
  };
}
