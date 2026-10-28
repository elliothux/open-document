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
      !integer(change.first, 1, axis === "rows" ? 1048576 : 16384) ||
      !integer(change.last, change.first, axis === "rows" ? 1048576 : 16384) ||
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

export function xlsxOutline(value: unknown): XlsxOutline {
  const outline = record(value);
  if (typeof outline.reason !== "string")
    throw new Error("Invalid outline reason");
  for (const name of ["rows", "columns"] as const) {
    const axis = record(outline[name]);
    if (
      typeof axis.summaryAfter !== "boolean" ||
      !Array.isArray(axis.groups) ||
      axis.groups.length > 1024
    )
      throw new Error("Invalid outline groups");
    const limit = name === "rows" ? 1048576 : 16384,
      seen = new Set<string>();
    for (const entry of axis.groups) {
      const group = record(entry);
      if (
        typeof group.first !== "number" ||
        typeof group.last !== "number" ||
        !integer(group.first, 1, limit) ||
        !integer(group.last, group.first, limit) ||
        !integer(group.level, 1, 7) ||
        group.summary !==
          (axis.summaryAfter ? group.last + 1 : group.first - 1) ||
        typeof group.collapsed !== "boolean"
      )
        throw new Error("Invalid outline group");
      const key = `${group.level}:${group.first}:${group.last}`;
      if (seen.has(key)) throw new Error("Duplicate outline group");
      seen.add(key);
    }
  }
  return value as XlsxOutline;
}
