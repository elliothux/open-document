import { type XlsxQuery } from "./xlsx-query.js";
import type { XlsxRuntime } from "./xlsx-session.js";
export const xlsxCommentCommands = {
  threadsXlsx(
    session: XlsxRuntime,
    {
      revision,
      sheet,
      cell,
    }: { revision: number; sheet: string; cell: string },
  ): XlsxThreads {
    return session.call<XlsxThreads>({
      operation: "threadsXlsx",
      revision,
      sheet,
      cell,
    });
  },
  editThreadXlsx(
    session: XlsxRuntime,
    {
      revision,
      sheet,
      change,
    }: { revision: number; sheet: string; change: XlsxThreadEdit },
  ) {
    checkXlsxThreadEdit(change);
    return session.call<XlsxQuery>({
      operation: "editThreadXlsx",
      revision,
      sheet,
      change,
    });
  },
};
import {
  checkXlsxThreadEdit,
  type XlsxThreads,
  type XlsxThreadEdit,
} from "./xlsx-comments.js";
