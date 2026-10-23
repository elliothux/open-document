import { integer, record } from "./validation.js";
export interface XlsxTimelineRange {
  start: string;
  end: string;
}
export interface XlsxTimelineSettings {
  pivot: string;
  field: number;
  name: string;
  caption: string;
  width: number;
  height: number;
}
export function checkXlsxTimelineSettings(value: unknown): void {
  const item = record(value),
    keys = ["pivot", "field", "name", "caption", "width", "height"];
  if (
    Object.keys(item).length !== keys.length ||
    !Object.keys(item).every((key) => keys.includes(key)) ||
    !text(item.pivot, false, 1024) ||
    !integer(item.field, 0, 63) ||
    !text(item.name) ||
    !text(item.caption) ||
    ![item.width, item.height].every(
      (value) =>
        typeof value === "number" &&
        Number.isFinite(value) &&
        value >= 0.1 &&
        value <= 14400,
    )
  )
    throw new Error("Invalid native timeline settings");
}
export interface XlsxTimelineEdit {
  action: "filterTimeline";
  name: string;
  range: XlsxTimelineRange | null;
}
export function checkXlsxTimelineEdit(value: unknown): void {
  const edit = record(value);
  if (
    Object.keys(edit).length !== 3 ||
    edit.action !== "filterTimeline" ||
    !text(edit.name) ||
    !("range" in edit)
  )
    throw new Error("Invalid timeline filter command");
  if (edit.range !== null) range(edit.range);
}
export interface XlsxTimelineView {
  name: string;
  label: string;
}
export function checkTimelineView(value: unknown): void {
  const view = record(value);
  if (
    Object.keys(view).length !== 2 ||
    !text(view.name) ||
    !text(view.label, false, 1024)
  )
    throw new Error("Invalid native timeline view");
}
export interface XlsxTimeline {
  part: string;
  name: string;
  caption: string;
  cache: string;
  cacheName: string;
  sourceName: string;
  pivotCache: string;
  field: number;
  connections: { sheet: string; part: string; name: string; field: number }[];
  state: {
    bounds: XlsxTimelineRange;
    selection: XlsxTimelineRange | null;
    singleRange: boolean;
    filterType: string;
    minimumRefreshVersion: number;
    lastRefreshVersion: number;
  };
  level: number;
  selectionLevel: number;
  scrollPosition: string | null;
  showHeader: boolean;
  showSelectionLabel: boolean;
  showTimeLevel: boolean;
  showHorizontalScrollbar: boolean;
  style: string;
}
export interface XlsxTimelines {
  revision: number;
  sheet: string;
  reason: string;
  items: XlsxTimeline[];
}
function text(value: unknown, empty = false, maximum = 255): value is string {
  return (
    typeof value === "string" &&
    (empty || !!value.trim()) &&
    value.length <= maximum &&
    value.isWellFormed() &&
    [...value].every(
      (char) => char.charCodeAt(0) >= 32 || "\t\n\r".includes(char),
    )
  );
}
function date(value: unknown): value is string {
  if (
    typeof value !== "string" ||
    value.length > 350 ||
    !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z?$/u.test(value)
  )
    return false;
  const head = value.slice(0, 19),
    parsed = new Date(head + "Z");
  return (
    Number.isFinite(parsed.valueOf()) &&
    parsed.toISOString().slice(0, 19) === head
  );
}
function range(value: unknown): void {
  const item = record(value);
  if (
    Object.keys(item).length !== 2 ||
    !date(item.start) ||
    !date(item.end) ||
    item.start.slice(0, 19) > item.end.slice(0, 19) ||
    (item.start.slice(0, 19) === item.end.slice(0, 19) &&
      item.start.slice(20).replace(/Z$/u, "").padEnd(350, "0") >
        item.end.slice(20).replace(/Z$/u, "").padEnd(350, "0"))
  )
    throw new Error("Invalid native timeline date range");
}
export function xlsxTimelines(value: unknown): XlsxTimelines {
  const catalog = record(value);
  if (
    !integer(catalog.revision, 0, 2147483647) ||
    typeof catalog.sheet !== "string" ||
    typeof catalog.reason !== "string" ||
    !Array.isArray(catalog.items) ||
    catalog.items.length > 64 ||
    (catalog.reason && catalog.items.length)
  )
    throw new Error("Invalid timeline catalog");
  const names = new Set<string>();
  for (const value of catalog.items) {
    const item = record(value),
      state = record(item.state);
    if (
      ![
        "part",
        "name",
        "caption",
        "cache",
        "cacheName",
        "sourceName",
        "pivotCache",
      ].every((key) =>
        text(
          item[key],
          false,
          ["part", "cache", "pivotCache"].includes(key) ? 1024 : 255,
        ),
      ) ||
      !text(item.style, true) ||
      !integer(item.field, 0, 79) ||
      !integer(item.level, 0, 3) ||
      !integer(item.selectionLevel, 0, 3) ||
      !(item.scrollPosition === null || date(item.scrollPosition)) ||
      ![
        "showHeader",
        "showSelectionLabel",
        "showTimeLevel",
        "showHorizontalScrollbar",
      ].every((key) => typeof item[key] === "boolean") ||
      !Array.isArray(item.connections) ||
      item.connections.length > 16 ||
      typeof state.singleRange !== "boolean" ||
      !text(state.filterType) ||
      !integer(state.minimumRefreshVersion, 0, 2147483647) ||
      !integer(state.lastRefreshVersion, 0, 2147483647)
    )
      throw new Error("Invalid native timeline metadata");
    const name = String(item.name).toLowerCase();
    if (names.has(name)) throw new Error("Duplicate timeline view");
    names.add(name);
    range(state.bounds);
    if (state.selection !== null) range(state.selection);
    const pivots = new Set<string>();
    for (const value of item.connections) {
      const connection = record(value);
      if (
        !text(connection.sheet, false, 1024) ||
        !text(connection.part, false, 1024) ||
        !text(connection.name) ||
        !integer(connection.field, 0, 79) ||
        pivots.has(connection.part)
      )
        throw new Error("Invalid timeline connection");
      pivots.add(connection.part);
    }
  }
  return value as XlsxTimelines;
}
