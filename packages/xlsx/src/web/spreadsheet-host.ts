import type { XlsxQuery } from "../core/xlsx.js";

/** Domain operations use the editor's current state and transaction barriers. */
export interface SpreadsheetHost {
  read<T>(action: () => Promise<T>, commitDraft?: boolean): Promise<T>;
  change(action: () => Promise<XlsxQuery>): Promise<void>;
  state(): XlsxQuery;
}
