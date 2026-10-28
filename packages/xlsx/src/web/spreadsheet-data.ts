import { SpreadsheetClipboard } from "./spreadsheet-clipboard-host.js";
import type {
  XlsxSubtotalSettings,
  XlsxDuplicateSettings,
  XlsxTextColumnSettings,
  XlsxConsolidateSettings,
} from "../core/xlsx.js";

export abstract class SpreadsheetData extends SpreadsheetClipboard {
  subtotals(settings: XlsxSubtotalSettings) {
    return this.read(() =>
      this.client.subtotals(
        this.currentState.revision,
        this.currentState.sheet,
        settings,
      ),
    );
  }
  duplicates(settings: XlsxDuplicateSettings) {
    return this.read(() =>
      this.client.duplicates(
        this.currentState.revision,
        this.currentState.sheet,
        settings,
      ),
    );
  }
  textColumns(settings: XlsxTextColumnSettings) {
    return this.read(() =>
      this.client.textColumns(
        this.currentState.revision,
        this.currentState.sheet,
        settings,
      ),
    );
  }
  consolidation(settings: XlsxConsolidateSettings) {
    return this.read(() =>
      this.client.consolidation(
        this.currentState.revision,
        this.currentState.sheet,
        settings,
      ),
    );
  }
}
