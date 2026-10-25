import type { XlsxThreadEdit } from "@open-document/wasm/xlsx";
export type XlsxCommentsRequest =
  | { operation: "threadsXlsx"; revision: number; sheet: string; cell: string }
  | {
      operation: "editThreadXlsx";
      revision: number;
      sheet: string;
      change: XlsxThreadEdit;
    };
