import { record, integer } from "./validation.js";
import { checkXlsxSort, type XlsxSortSettings } from "./xlsx-sort.js";
import { checkXlsxFilter, type XlsxFilterSettings } from "./xlsx-filter.js";
import {
  checkXlsxConditionalFormat,
  type XlsxConditionalFormat,
} from "./xlsx-conditional.js";
import {
  checkXlsxDataValidation,
  type XlsxDataValidation,
} from "./xlsx-validation.js";
import {
  checkXlsxPrintSetup,
  checkXlsxPrintRange,
  checkXlsxHeaderFooter,
  type XlsxPrintSetup,
  type XlsxPrintRange,
  type XlsxHeaderFooter,
} from "./xlsx-print.js";

export type XlsxSheetEdit =
  | ({ action: "filter" } & XlsxFilterSettings)
  | { action: "filterClear" | "filterRemove" | "filterReapply" }
  | ({ action: "sort"; range: string } & XlsxSortSettings)
  | {
      action: "conditionalRule";
      ranges: string;
      priority: number | null;
      rule: XlsxConditionalFormat | null;
      sourceRevision: number;
    }
  | {
      action: "conditionalPriority";
      priority: number;
      position: number;
      sourceRevision: number;
    }
  | { action: "validation"; range: string; rule: XlsxDataValidation | null }
  | { action: "validationValue"; index: number; sourceRevision: number }
  | {
      action: "fill";
      range: string;
      direction: "down" | "up" | "right" | "left";
    }
  | { action: "insertCells"; range: string; direction: "down" | "right" }
  | { action: "deleteCells"; range: string; direction: "up" | "left" }
  | ({ action: "pageSetup" } & XlsxPrintSetup)
  | ({ action: "printRange" } & XlsxPrintRange)
  | ({ action: "headerFooter" } & XlsxHeaderFooter)
  | { action: "freeze"; rows: number; columns: number }
  | {
      action: "view";
      gridLines: boolean;
      headings: boolean;
      rtl: boolean;
      formulas: boolean;
    }
  | { action: "merge"; range: string; discard: boolean }
  | { action: "unmerge"; range: string }
  | { action: "add" }
  | { action: "copy" }
  | { action: "delete" }
  | { action: "move"; index: number }
  | { action: "rename"; name: string }
  | {
      action: "insertRows" | "deleteRows" | "insertColumns" | "deleteColumns";
      first: number;
      count: number;
    }
  | {
      action: "rowHeight" | "columnWidth";
      first: number;
      last: number;
      size: number;
    }
  | { action: "visibility"; state: "visible" | "hidden" | "veryHidden" };

export function checkXlsxSheetEdit(value: unknown): void {
  const change = record(value);
  if (change.action === "view") {
    if (
      typeof change.gridLines !== "boolean" ||
      typeof change.headings !== "boolean" ||
      typeof change.rtl !== "boolean" ||
      typeof change.formulas !== "boolean" ||
      Object.keys(change).some(
        (key) =>
          !["action", "gridLines", "headings", "rtl", "formulas"].includes(key),
      )
    )
      throw new Error("Invalid worksheet view");
    return;
  }
  if (change.action === "filter") {
    checkXlsxFilter(change);
    return;
  }
  if (
    ["filterClear", "filterRemove", "filterReapply"].includes(
      String(change.action),
    )
  )
    return;
  if (change.action === "sort") {
    checkXlsxSort(change);
    return;
  }
  if (
    change.action === "conditionalRule" ||
    change.action === "conditionalPriority"
  ) {
    if (!integer(change.sourceRevision, 0, 2147483647))
      throw new Error("Invalid conditional source revision");
    if (change.action === "conditionalPriority") {
      if (
        !integer(change.priority, 1, 2147483647) ||
        !integer(change.position, 0, 4095)
      )
        throw new Error("Invalid conditional priority");
    } else {
      if (
        (change.priority !== null &&
          !integer(change.priority, 1, 2147483647)) ||
        typeof change.ranges !== "string" ||
        change.ranges.length > 262144 ||
        (!change.ranges && (change.rule !== null || change.priority === null))
      )
        throw new Error("Invalid conditional ranges or priority");
      if (change.rule !== null) checkXlsxConditionalFormat(change.rule);
    }
    return;
  }
  if (change.action === "validation") {
    if (
      typeof change.range !== "string" ||
      !change.range ||
      change.range.length > 64
    )
      throw new Error("Invalid data validation range");
    if (change.rule !== null) checkXlsxDataValidation(change.rule);
    return;
  }
  if (change.action === "validationValue") {
    if (
      !integer(change.index, 0, 4095) ||
      !integer(change.sourceRevision, 0, 2147483647)
    )
      throw new Error("Invalid validation list index");
    return;
  }
  if (change.action === "fill") {
    if (
      typeof change.range !== "string" ||
      !change.range ||
      change.range.length > 64 ||
      !["down", "up", "right", "left"].includes(String(change.direction))
    )
      throw new Error("Invalid cell fill");
    return;
  }
  if (change.action === "insertCells" || change.action === "deleteCells") {
    if (
      typeof change.range !== "string" ||
      typeof change.direction !== "string" ||
      !change.range ||
      change.range.length > 64 ||
      !(
        change.action === "insertCells" ? ["down", "right"] : ["up", "left"]
      ).includes(String(change.direction))
    )
      throw new Error("Invalid cell shift");
    return;
  }
  if (
    ["insertRows", "deleteRows", "insertColumns", "deleteColumns"].includes(
      String(change.action),
    )
  ) {
    const limit = String(change.action).endsWith("Rows") ? 1048576 : 16384;
    if (
      !integer(change.first, 1, limit) ||
      !integer(
        change.count,
        1,
        Math.min(4096, limit - Number(change.first) + 1),
      )
    )
      throw new Error("Invalid structural row or column interval");
    return;
  }
  if (change.action === "headerFooter") {
    checkXlsxHeaderFooter(change);
    return;
  }
  if (change.action === "printRange") {
    checkXlsxPrintRange(change);
    return;
  }
  if (change.action === "pageSetup") {
    checkXlsxPrintSetup(change);
    return;
  }
  if (
    change.action === "freeze" &&
    integer(change.rows, 0, 1048575) &&
    integer(change.columns, 0, 16383)
  )
    return;
  if (
    (change.action === "merge" || change.action === "unmerge") &&
    typeof change.range === "string" &&
    change.range.length > 0 &&
    change.range.length <= 64 &&
    (change.action === "unmerge" || typeof change.discard === "boolean")
  )
    return;
  if (
    change.action === "add" ||
    change.action === "copy" ||
    change.action === "delete"
  )
    return;
  if (
    (change.action === "rowHeight" || change.action === "columnWidth") &&
    integer(change.first, 1, change.action === "rowHeight" ? 1048576 : 16384) &&
    integer(
      change.last,
      Number(change.first),
      change.action === "rowHeight" ? 1048576 : 16384,
    ) &&
    typeof change.size === "number" &&
    Number.isFinite(change.size) &&
    change.size >= 0 &&
    change.size <= (change.action === "rowHeight" ? 409.5 : 255)
  )
    return;
  if (
    change.action === "rename" &&
    typeof change.name === "string" &&
    change.name.length > 0 &&
    change.name.length <= 31 &&
    change.name.isWellFormed() &&
    !change.name.startsWith("'") &&
    !change.name.endsWith("'") &&
    !Array.from(change.name).some(
      (character) =>
        character.charCodeAt(0) < 32 || "[]:*?/\\".includes(character),
    ) &&
    !change.name.includes("\ufffe") &&
    !change.name.includes("\uffff")
  )
    return;
  if (change.action === "move" && integer(change.index, 0, 255)) return;
  if (
    change.action === "visibility" &&
    ["visible", "hidden", "veryHidden"].includes(String(change.state))
  )
    return;
  throw new Error("Invalid worksheet edit");
}
