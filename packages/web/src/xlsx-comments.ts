import { XlsxDrawingClient } from "./xlsx-drawings.js";
import {
  checkXlsxThreadEdit,
  xlsxThreads,
  xlsxQuery,
  type XlsxThreadEdit,
} from "@open-document/wasm/xlsx";
export {
  checkXlsxThreadEdit,
  xlsxThreads,
  type XlsxThreadEdit,
  type XlsxThreads,
} from "@open-document/wasm/xlsx";

export class XlsxCommentsClient extends XlsxDrawingClient {
  async threads(revision: number, sheet: string, cell: string) {
    return xlsxThreads(
      await this.connection.request({
        operation: "threadsXlsx",
        revision,
        sheet,
        cell,
      }),
    );
  }
  async editThread(revision: number, sheet: string, change: XlsxThreadEdit) {
    checkXlsxThreadEdit(change);
    return xlsxQuery(
      await this.connection.request({
        operation: "editThreadXlsx",
        revision,
        sheet,
        change,
      }),
    );
  }
}
