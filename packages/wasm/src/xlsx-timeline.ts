import { integer, record } from "./validation.js";
import {
  checkDrawingFrameView,
  type XlsxDrawingFrame,
} from "./xlsx-drawing-frame.js";
import {
  drawingRegions,
  type XlsxDrawingRegion,
} from "./xlsx-drawing-pointer.js";
import { xlsxViewport, type XlsxViewport } from "./xlsx.js";
import { xlsxQuery, type XlsxQuery } from "./xlsx-query.js";

export interface XlsxTimelineGesture {
  handle: number;
  first: number;
  position: number;
  x: number;
  y: number;
  commit: boolean;
}
export interface XlsxTimelinePreview {
  query: XlsxQuery | null;
  drawing: XlsxViewport | null;
}
export function checkXlsxTimelineGesture(input: unknown): void {
  const value = record(input);
  if (
    Object.keys(value).length !== 6 ||
    !integer(value.handle, 0, 2) ||
    !integer(value.first, 0, 3000000) ||
    !integer(value.position, 0, 3000000) ||
    ![value.x, value.y].every(
      (number) =>
        typeof number === "number" &&
        Number.isFinite(number) &&
        Math.abs(number) <= 14400,
    ) ||
    typeof value.commit !== "boolean"
  )
    throw new Error("Invalid timeline gesture");
}
export function xlsxTimelinePreview(value: unknown): XlsxTimelinePreview {
  const result = record(value);
  if (
    Object.keys(result).length !== 2 ||
    (result.query === null) === (result.drawing === null)
  )
    throw new Error("Invalid timeline preview state");
  if (result.query !== null) xlsxQuery(result.query);
  if (result.drawing !== null) xlsxViewport(result.drawing);
  return value as XlsxTimelinePreview;
}
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
export type XlsxTimelineEdit =
  | {
      action: "setTimelineEndpoint";
      name: string;
      handle: number;
      level: number;
      position: number;
    }
  | { action: "setTimelineLevel"; name: string; level: number }
  | { action: "scrollTimeline"; name: string; level: number; position: number }
  | { action: "deleteTimeline"; name: string }
  | { action: "filterTimeline"; name: string; range: XlsxTimelineRange | null };
export function checkXlsxTimelineEdit(value: unknown): void {
  const edit = record(value);
  if (edit.action === "setTimelineEndpoint") {
    if (
      Object.keys(edit).length !== 5 ||
      !text(edit.name) ||
      !integer(edit.handle, 1, 2) ||
      !integer(edit.level, 0, 3) ||
      !integer(edit.position, 0, 3000000)
    )
      throw new Error("Invalid timeline endpoint command");
    return;
  }
  if (edit.action === "setTimelineLevel" || edit.action === "scrollTimeline") {
    const scrolling = edit.action === "scrollTimeline";
    if (
      Object.keys(edit).length !== (scrolling ? 4 : 3) ||
      !text(edit.name) ||
      !integer(edit.level, 0, 3) ||
      (scrolling && !integer(edit.position, 0, 3000000))
    )
      throw new Error("Invalid timeline view command");
    return;
  }
  if (edit.action === "deleteTimeline") {
    if (Object.keys(edit).length !== 2 || !text(edit.name))
      throw new Error("Invalid timeline deletion command");
    return;
  }
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
  frame: XlsxDrawingFrame;
  move: XlsxDrawingRegion[];
  handles: {
    handle: number;
    index: number;
    value: string;
    regions: XlsxDrawingRegion[];
  }[];
  navigation: {
    level: number;
    minimum: number;
    maximum: number;
    position: number;
    label: string;
    levelRegions: XlsxDrawingRegion[];
    scrollRegions: XlsxDrawingRegion[];
  };
  periods: {
    index: number;
    label: string;
    selected: boolean;
    regions: XlsxDrawingRegion[];
  }[];
}
export function checkTimelineView(value: unknown): void {
  const view = record(value);
  if (
    Object.keys(view).length !== 7 ||
    !text(view.name) ||
    !text(view.label, false, 1024)
  )
    throw new Error("Invalid native timeline view");
  checkDrawingFrameView(view.frame);
  drawingRegions(view.move);
  if (!Array.isArray(view.handles) || view.handles.length > 2)
    throw new Error("Invalid timeline endpoint handles");
  let previousHandle = 0;
  for (const value of view.handles) {
    const handle = record(value);
    if (
      Object.keys(handle).length !== 4 ||
      !integer(handle.handle, 1, 2) ||
      Number(handle.handle) <= previousHandle ||
      !integer(handle.index, 0, 3000000) ||
      !date(handle.value)
    )
      throw new Error("Invalid timeline endpoint handle");
    drawingRegions(handle.regions);
    if (!handle.regions.length)
      throw new Error("Timeline endpoint is not visible");
    previousHandle = Number(handle.handle);
  }
  const navigation = record(view.navigation);
  if (
    Object.keys(navigation).length !== 7 ||
    !integer(navigation.level, 0, 3) ||
    !integer(navigation.minimum, 0, 3000000) ||
    !integer(navigation.maximum, Number(navigation.minimum), 3000000) ||
    !integer(
      navigation.position,
      Number(navigation.minimum),
      Number(navigation.maximum),
    ) ||
    !text(navigation.label)
  )
    throw new Error("Invalid timeline navigation");
  drawingRegions(navigation.levelRegions);
  drawingRegions(navigation.scrollRegions);
  if (!Array.isArray(view.periods) || view.periods.length > 512)
    throw new Error("Invalid timeline periods");
  let previous = -1;
  for (const value of view.periods) {
    const period = record(value);
    if (
      Object.keys(period).length !== 4 ||
      !integer(period.index, 0, 3000000) ||
      Number(period.index) <= previous ||
      !text(period.label) ||
      typeof period.selected !== "boolean"
    )
      throw new Error("Invalid timeline period");
    drawingRegions(period.regions);
    if (!period.regions.length)
      throw new Error("Timeline period is not visible");
    previous = Number(period.index);
  }
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
