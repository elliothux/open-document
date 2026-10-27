import { XlsxCommentsClient } from "./xlsx-comments.js";
import {
  checkXlsxSubtotalSettings,
  xlsxSubtotals,
  type XlsxSubtotalSettings,
  checkXlsxDuplicateSettings,
  xlsxDuplicates,
  type XlsxDuplicateSettings,
  checkXlsxTextColumnSettings,
  xlsxTextColumns,
  type XlsxTextColumnSettings,
  checkXlsxConsolidateSettings,
  xlsxConsolidation,
  type XlsxConsolidateSettings,
} from "@open-document/wasm/xlsx";

export class XlsxDataClient extends XlsxCommentsClient {
  async subtotals(
    revision: number,
    sheet: string,
    settings: XlsxSubtotalSettings,
  ) {
    checkXlsxSubtotalSettings(settings);
    return xlsxSubtotals(
      await this.connection.request({
        operation: "subtotalsXlsx",
        revision,
        sheet,
        settings,
      }),
    );
  }
  async duplicates(
    revision: number,
    sheet: string,
    settings: XlsxDuplicateSettings,
  ) {
    checkXlsxDuplicateSettings(settings);
    return xlsxDuplicates(
      await this.connection.request({
        operation: "duplicatesXlsx",
        revision,
        sheet,
        settings,
      }),
    );
  }
  async textColumns(
    revision: number,
    sheet: string,
    settings: XlsxTextColumnSettings,
  ) {
    checkXlsxTextColumnSettings(settings);
    return xlsxTextColumns(
      await this.connection.request({
        operation: "textColumnsXlsx",
        revision,
        sheet,
        settings,
      }),
    );
  }
  async consolidation(
    revision: number,
    sheet: string,
    settings: XlsxConsolidateSettings,
  ) {
    checkXlsxConsolidateSettings(settings);
    return xlsxConsolidation(
      await this.connection.request({
        operation: "consolidationXlsx",
        revision,
        sheet,
        settings,
      }),
    );
  }
}
