import { integer, record } from "./validation.js";

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

export function xlsxStatistics(value: unknown): XlsxStatistics {
  const state = record(value);
  const finite = (value: unknown): value is number =>
    typeof value === "number" && Number.isFinite(value);
  if (
    typeof state.range !== "string" ||
    !state.range ||
    state.range.length > 32 ||
    !integer(state.count, 0, 4096) ||
    !integer(state.countNumbers, 0, Number(state.count)) ||
    typeof state.reason !== "string" ||
    Object.keys(state).some(
      (key) =>
        ![
          "range",
          "count",
          "countNumbers",
          "sum",
          "average",
          "min",
          "max",
          "reason",
        ].includes(key),
    ) ||
    (state.countNumbers === 0 ||
    (state.reason.length > 0 &&
      [state.sum, state.average, state.min, state.max].every((v) => v === null))
      ? [state.sum, state.average, state.min, state.max].some((v) => v !== null)
      : !finite(state.min) ||
        !finite(state.max) ||
        state.min > state.max ||
        !finite(state.average) ||
        state.average < state.min ||
        state.average > state.max ||
        !(finite(state.sum) || (state.sum === null && state.reason.length > 0)))
  )
    throw new Error("Invalid selection statistics");
  return value as XlsxStatistics;
}
