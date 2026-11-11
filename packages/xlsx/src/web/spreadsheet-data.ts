import type { SpreadsheetHost } from "./spreadsheet-host.js";
import type { XlsxClient } from "./xlsx.js";
import type {
  XlsxSubtotalSettings,
  XlsxDuplicateSettings,
  XlsxTextColumnSettings,
  XlsxConsolidateSettings,
} from "../core/xlsx.js";

export function createSpreadsheetData(
  client: XlsxClient,
  host: SpreadsheetHost,
) {
  return {
    numberFormatSamples(formats: readonly string[]) {
      return host.read(
        () => client.execute({ operation: "numberFormatSamplesXlsx", formats }),
        false,
      );
    },
    recalculate(): Promise<void> {
      return host.change(() =>
        client.execute({
          operation: "recalculateXlsx",
          revision: host.state().revision,
        }),
      );
    },
    subtotals(settings: XlsxSubtotalSettings) {
      return host.read(() =>
        client.execute({
          operation: "subtotalsXlsx",
          revision: host.state().revision,
          sheet: host.state().sheet,
          settings: settings,
        }),
      );
    },
    duplicates(settings: XlsxDuplicateSettings) {
      return host.read(() =>
        client.execute({
          operation: "duplicatesXlsx",
          revision: host.state().revision,
          sheet: host.state().sheet,
          settings: settings,
        }),
      );
    },
    textColumns(settings: XlsxTextColumnSettings) {
      return host.read(() =>
        client.execute({
          operation: "textColumnsXlsx",
          revision: host.state().revision,
          sheet: host.state().sheet,
          settings: settings,
        }),
      );
    },
    consolidation(settings: XlsxConsolidateSettings) {
      return host.read(() =>
        client.execute({
          operation: "consolidationXlsx",
          revision: host.state().revision,
          sheet: host.state().sheet,
          settings: settings,
        }),
      );
    },
  };
}
