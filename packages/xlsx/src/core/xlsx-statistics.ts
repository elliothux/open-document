export interface XlsxStatistics {
  /** Queried rectangle; hidden rows and empty text are excluded. */
  range: string;
  count: number;
  countNumbers: number;
  /** Raw numeric values, including numeric formula results and date serials. */
  sum: number | null;
  average: number | null;
  min: number | null;
  max: number | null;
  /** Uncalculated formulas, read-only source or numeric overflow; counts remain available. */
  reason: string;
}
