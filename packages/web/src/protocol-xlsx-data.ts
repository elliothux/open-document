import type {
  XlsxDuplicateSettings,
  XlsxTextColumnSettings,
  XlsxConsolidateSettings,
  XlsxSubtotalSettings,
} from "@open-document/wasm/xlsx";

export type XlsxDataRequest =
  | {
      operation: "subtotalsXlsx";
      revision: number;
      sheet: string;
      settings: XlsxSubtotalSettings;
    }
  | {
      operation: "duplicatesXlsx";
      revision: number;
      sheet: string;
      settings: XlsxDuplicateSettings;
    }
  | {
      operation: "textColumnsXlsx";
      revision: number;
      sheet: string;
      settings: XlsxTextColumnSettings;
    }
  | {
      operation: "consolidationXlsx";
      revision: number;
      sheet: string;
      settings: XlsxConsolidateSettings;
    };
