import type { XlsxPasteMode } from "@open-document/wasm/xlsx";
import { SpreadsheetObjects } from "./spreadsheet-objects.js";
import {
  copyCellData,
  copySpreadsheetDrawing,
  pasteSpreadsheetCells,
  cutSpreadsheetDrawing,
  pasteSpreadsheetDrawing,
} from "./spreadsheet-clipboard.js";

/** Clipboard access uses the editor's draft barrier, queue and disposal checks. */
export abstract class SpreadsheetClipboard extends SpreadsheetObjects {
  acceptValidationWarnings = false;
  protected abstract closed: boolean;
  protected abstract get selectedDrawing(): string | undefined;

  paste(text: string): Promise<void> {
    return this.change(() =>
      this.client.paste(
        this.currentState.revision,
        text,
        this.acceptValidationWarnings,
      ),
    );
  }
  copyCells(cut = false): Promise<void> {
    return this.read(() =>
      copyCellData(this.client, this.currentState, true, cut),
    );
  }
  pasteCells(mode: XlsxPasteMode = "all", transpose = false): Promise<void> {
    return this.change(() =>
      pasteSpreadsheetCells(
        this.client,
        this.currentState,
        this.profile,
        mode,
        transpose,
        this.acceptValidationWarnings,
        () => this.closed,
      ),
    );
  }
  copy(): Promise<void> {
    return this.read(() =>
      this.selectedDrawing
        ? copySpreadsheetDrawing(
            this.client,
            this.currentState,
            this.selectedDrawing,
            this.profile,
          )
        : copyCellData(this.client, this.currentState, false),
    );
  }
  copyDrawing(id: string): Promise<void> {
    return this.read(() =>
      copySpreadsheetDrawing(this.client, this.currentState, id, this.profile),
    );
  }
  cutSelection(): Promise<void> {
    return this.read(() =>
      this.selectedDrawing
        ? cutSpreadsheetDrawing(
            this.client,
            this.currentState,
            this.selectedDrawing,
          )
        : copyCellData(this.client, this.currentState, true, true),
    );
  }
  cutDrawing(id: string): Promise<void> {
    return this.read(() =>
      cutSpreadsheetDrawing(this.client, this.currentState, id),
    );
  }
  pasteDrawing(): Promise<void> {
    return this.change(() =>
      pasteSpreadsheetDrawing(
        this.client,
        this.currentState,
        this.profile,
        () => this.closed,
        async (fragment) => {
          const bytes = await this.client.drawingFragmentImage(
            this.currentState.revision,
            fragment,
          );
          if (bytes)
            await this.surface.addPicture(
              this.client,
              this.currentState.revision,
              bytes,
            );
        },
      ),
    );
  }
}
