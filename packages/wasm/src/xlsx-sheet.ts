import { record, integer } from "./validation.js";
import { checkXlsxNameEdit, type XlsxNameEdit } from "./xlsx-names.js";
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
  | { action: "note"; cell: string; text: string | null; author?: string }
  | { action: "hyperlink"; range: string; target: string | null }
  | { action: "openHyperlink"; range: string; sourceRevision: number }
  | XlsxNameEdit
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
  | {
      action: "series";
      mode: "linear" | "growth" | "text" | "auto" | "copy" | "shrink";
      source: string;
      range: string;
      direction: "down" | "up" | "right" | "left";
    }
  | {
      action: "series";
      mode: "date";
      unit: "day" | "weekday" | "month" | "year";
      step: number;
      source: string;
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
  if (change.action === "note") {
    if (
      !noteCell(change.cell) ||
      (change.text !== null && !noteText(change.text, 32767, true)) ||
      (change.author !== undefined &&
        (!noteText(change.author, 255, true) ||
          Array.from(change.author).some((c) => c.codePointAt(0)! < 32))) ||
      Object.keys(change).some(
        (key) => !["action", "cell", "text", "author"].includes(key),
      )
    )
      throw new Error("Invalid cell note edit");
    return;
  }
  if (change.action === "hyperlink" || change.action === "openHyperlink") {
    const fields =
      change.action === "hyperlink"
        ? ["action", "range", "target"]
        : ["action", "range", "sourceRevision"];
    if (
      Object.keys(change).length !== fields.length ||
      Object.keys(change).some((k) => !fields.includes(k))
    )
      throw new Error("Invalid hyperlink fields");
    if (
      typeof change.range !== "string" ||
      !change.range ||
      change.range.length > 64
    )
      throw new Error("Invalid hyperlink range");
    if (change.action === "hyperlink") {
      checkXlsxHyperlinkTarget(change.target);
    } else if (!integer(change.sourceRevision, 0, 2147483647))
      throw new Error("Invalid hyperlink revision");
    return;
  }
  if (["name", "nameDelete", "nameSelect"].includes(String(change.action))) {
    checkXlsxNameEdit(change);
    return;
  }
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
  if (change.action === "fill" || change.action === "series") {
    if (
      change.action === "series" &&
      change.mode === "shrink" &&
      !["up", "left"].includes(String(change.direction))
    )
      throw new Error("Shrink must clear trailing rows or columns");
    if (
      typeof change.range !== "string" ||
      !change.range ||
      change.range.length > 64 ||
      !["down", "up", "right", "left"].includes(String(change.direction))
    )
      throw new Error("Invalid cell fill");
    if (
      change.action === "series" &&
      (typeof change.source !== "string" ||
        !change.source ||
        change.source.length > 64 ||
        typeof change.mode !== "string" ||
        ![
          "linear",
          "growth",
          "date",
          "text",
          "auto",
          "copy",
          "shrink",
        ].includes(change.mode) ||
        Object.keys(change).some(
          (key) =>
            ![
              "action",
              "mode",
              "source",
              "range",
              "direction",
              ...(change.mode === "date" ? ["unit", "step"] : []),
            ].includes(key),
        ))
    )
      throw new Error("Invalid series source or mode");
    if (
      change.action === "series" &&
      change.mode === "date" &&
      (typeof change.unit !== "string" ||
        !["day", "weekday", "month", "year"].includes(change.unit) ||
        typeof change.step !== "number" ||
        !Number.isFinite(change.step) ||
        Math.abs(change.step) > 2958465 ||
        (change.unit !== "day" && !Number.isInteger(change.step)))
    )
      throw new Error("Invalid date series unit or step");
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

export interface XlsxNote {
  address: string;
  text: string;
  author: string;
  exists: boolean;
  reason: string;
}
function noteCell(value: unknown): value is string {
  if (typeof value !== "string") return false;
  const match = /^([A-Z]{1,3})([1-9]\d{0,6})$/iu.exec(value);
  return (
    !!match &&
    match[0] === value &&
    Number(match[2]) <= 1048576 &&
    Array.from(match[1]!.toUpperCase()).reduce(
      (sum, c) => sum * 26 + c.charCodeAt(0) - 64,
      0,
    ) <= 16384
  );
}
function noteText(
  value: unknown,
  max: number,
  required = false,
): value is string {
  return (
    typeof value === "string" &&
    value.length <= max &&
    value.isWellFormed() &&
    (!required || !!value.trim()) &&
    !Array.from(value).some((c) => {
      const n = c.codePointAt(0)!;
      return (n < 32 && ![9, 10, 13].includes(n)) || n === 65534 || n === 65535;
    })
  );
}
export function xlsxNote(value: unknown): XlsxNote {
  const result = record(value);
  if (
    typeof result.reason !== "string" ||
    typeof result.exists !== "boolean" ||
    typeof result.address !== "string" ||
    (!(result.reason && !result.address) && !noteCell(result.address)) ||
    result.address !== result.address.toUpperCase() ||
    (!result.exists && (result.text !== "" || result.author !== "")) ||
    !noteText(result.text, 32767) ||
    !noteText(result.author, 255)
  )
    throw new Error("Invalid cell note query");
  return value as XlsxNote;
}

export interface XlsxHyperlink {
  target: string | null;
  mixed: boolean;
  readOnlyReason: string;
  navigationReason: string;
}

export function checkXlsxHyperlinkTarget(target: unknown): void {
  if (target === null) return;
  if (
    typeof target !== "string" ||
    !target.isWellFormed() ||
    !target ||
    target.length > 2048 ||
    Array.from(target).some(
      (c) =>
        c.charCodeAt(0) < 32 ||
        c.charCodeAt(0) === 127 ||
        c.charCodeAt(0) >= 65534 ||
        c === "\\",
    ) ||
    (target.startsWith("#")
      ? target.length === 1
      : !/^(https?:\/\/|mailto:).+/i.test(target) || /\s/u.test(target))
  )
    throw new Error("Invalid XLSX hyperlink target");
}

export function xlsxHyperlink(value: unknown): XlsxHyperlink {
  const link = record(value);
  checkXlsxHyperlinkTarget(link.target);
  if (
    typeof link.mixed !== "boolean" ||
    typeof link.readOnlyReason !== "string" ||
    typeof link.navigationReason !== "string" ||
    (link.mixed && link.target !== null)
  )
    throw new Error("Invalid XLSX hyperlink query");
  return value as XlsxHyperlink;
}
