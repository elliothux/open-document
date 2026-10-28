import type { XlsxThreadEdit } from "../core/xlsx.js";
export type XlsxCommentsRequest =
  | { operation: "threadsXlsx"; revision: number; sheet: string; cell: string }
  | {
      operation: "editThreadXlsx";
      revision: number;
      sheet: string;
      change: XlsxThreadEdit;
    };
