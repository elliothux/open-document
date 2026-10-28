import type { XlsxSession } from "../core/xlsx.js";
import type { Operation } from "./protocol.js";
import type { XlsxCommentsRequest } from "./protocol-xlsx-comments.js";

export function isXlsxCommentsRequest(
  request: Operation,
): request is Operation & XlsxCommentsRequest {
  return (
    request.operation === "threadsXlsx" ||
    request.operation === "editThreadXlsx"
  );
}
export function commentsOperation(
  workbook: XlsxSession | undefined,
  request: XlsxCommentsRequest,
): unknown {
  if (!workbook) throw new Error("Open an XLSX client first");
  return request.operation === "threadsXlsx"
    ? workbook.threads(request.revision, request.sheet, request.cell)
    : workbook.editThread(request.revision, request.sheet, request.change);
}
