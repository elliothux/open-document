import {
  xlsxWorksheetColumns,
  xlsxWorksheetRows,
} from "@open-document/wasm/engine-source";
import { record, integer } from "@open-document/wasm/abi/validation";

export interface XlsxOutlineGroup {
  first: number;
  last: number;
  level: number;
  summary: number;
  collapsed: boolean;
}
export interface XlsxOutline {
  rows: { summaryAfter: boolean; groups: XlsxOutlineGroup[] };
  columns: { summaryAfter: boolean; groups: XlsxOutlineGroup[] };
  reason: string;
}
export type XlsxOutlineEdit =
  | {
      action: "group" | "ungroup";
      axis: "rows" | "columns";
      first: number;
      last: number;
    }
  | {
      action: "collapseGroup";
      axis: "rows" | "columns";
      first: number;
      last: number;
      level: number;
      collapsed: boolean;
    }
  | { action: "clearOutline"; axis: "rows" | "columns" }
  | { action: "outlineSummary"; axis: "rows" | "columns"; after: boolean };

export function checkXlsxOutlineEdit(value: unknown): void {
  const change = record(value),
    axis = change.axis;
  if (axis !== "rows" && axis !== "columns")
    throw new Error("Invalid outline axis");
  let keys: string[];
  if (change.action === "clearOutline") keys = ["action", "axis"];
  else if (
    change.action === "outlineSummary" &&
    typeof change.after === "boolean"
  )
    keys = ["action", "axis", "after"];
  else if (
    change.action === "group" ||
    change.action === "ungroup" ||
    change.action === "collapseGroup"
  ) {
    if (
      typeof change.first !== "number" ||
      typeof change.last !== "number" ||
      !integer(
        change.first,
        1,
        axis === "rows" ? xlsxWorksheetRows : xlsxWorksheetColumns,
      ) ||
      !integer(
        change.last,
        change.first,
        axis === "rows" ? xlsxWorksheetRows : xlsxWorksheetColumns,
      ) ||
      change.last - change.first >= 4095
    )
      throw new Error("Invalid outline interval");
    keys = ["action", "axis", "first", "last"];
    if (change.action === "collapseGroup") {
      if (!integer(change.level, 1, 7) || typeof change.collapsed !== "boolean")
        throw new Error("Invalid outline collapse");
      keys.push("level", "collapsed");
    }
  } else throw new Error("Invalid outline edit");
  if (
    Object.keys(change).length !== keys.length ||
    Object.keys(change).some((key) => !keys.includes(key))
  )
    throw new Error("Invalid outline edit fields");
}
