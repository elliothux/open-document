import type { XlsxQuery } from "../core/xlsx.js";

/** Domain operations use the editor's current state and transaction barriers. */
export interface SpreadsheetHost {
  read<T>(action: () => Promise<T>): Promise<T>;
  change(action: () => Promise<XlsxQuery>): Promise<void>;
  state(): XlsxQuery;
}
