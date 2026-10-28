import type { DocxSelection } from "./docx-hit.js";
import { isDocxSelection } from "./docx-search.js";
import { integer, record } from "@open-document/wasm/abi/validation";
import { editState, type EditState } from "./docx-format.js";

export type DocxCommentEdit =
  | {
      action: "add" | "addWord";
      text: string;
      author: string;
      initials: string;
      date: string;
      selection: DocxSelection;
    }
  | { action: "update"; id: string; text: string }
  | {
      action: "reply";
      id: string;
      text: string;
      author: string;
      initials: string;
      date: string;
    }
  | { action: "resolve"; id: string; done: boolean }
  | { action: "remove" | "goTo"; id: string };
export interface DocxComments {
  revision: number;
  reason: string;
  items: {
    id: string;
    text: string;
    author: string;
    initials: string;
    date: string;
    parent: string | null;
    done: boolean;
    selection: DocxSelection | null;
    reason: string;
  }[];
}

export interface DocxCommentNavigation {
  comment: string | null;
  state: EditState;
}

export function docxCommentNavigation(value: unknown): DocxCommentNavigation {
  const result = record(value);
  const state = editState(result.state);
  const comment = result.comment;
  if (comment !== null && (!id(comment) || state.selection === null))
    throw new Error("Invalid comment navigation");
  return { comment, state };
}

export interface DocxCommentLayout {
  reason: string;
  items: {
    id: string;
    reason: string;
    rects: {
      page: number;
      line: number;
      x: number;
      y: number;
      width: number;
      height: number;
    }[];
  }[];
}

export function docxCommentLayout(
  value: unknown,
  pages: { width: number; height: number }[],
): DocxCommentLayout {
  const layout = record(value);
  if (
    !text(layout.reason, 32767) ||
    !Array.isArray(layout.items) ||
    layout.items.length > 4096 ||
    (layout.reason && layout.items.length)
  )
    throw new Error("Invalid comment layout");
  const seen = new Set<string>();
  let count = 0;
  for (const raw of layout.items) {
    const item = record(raw);
    if (
      !id(item.id) ||
      seen.has(item.id) ||
      !text(item.reason, 32767) ||
      !Array.isArray(item.rects) ||
      (item.reason && item.rects.length)
    )
      throw new Error("Invalid comment layout item");
    seen.add(item.id);
    count += item.rects.length;
    if (count > 65536) throw new Error("Comment rectangles exceed budget");
    for (const raw of item.rects) {
      const rect = record(raw);
      if (
        !integer(rect.page, 0, pages.length - 1) ||
        !integer(rect.line, 0, 2147483647) ||
        ![rect.x, rect.y, rect.width, rect.height].every(
          (v) => typeof v === "number" && Number.isFinite(v),
        )
      )
        throw new Error("Invalid comment rectangle");
      const page = pages[Number(rect.page)]!;
      if (
        Number(rect.x) < 0 ||
        Number(rect.y) < 0 ||
        Number(rect.width) <= 0 ||
        Number(rect.height) <= 0 ||
        Number(rect.x) + Number(rect.width) > page.width + 0.001 ||
        Number(rect.y) + Number(rect.height) > page.height + 0.001
      )
        throw new Error("Comment rectangle is outside the page");
    }
  }
  return value as DocxCommentLayout;
}
function text(value: unknown, max: number, required = false): value is string {
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
function id(value: unknown): value is string {
  return (
    typeof value === "string" &&
    integer(Number(value), 0, 2147483647) &&
    String(Number(value)) === value
  );
}
export function checkDocxComment(
  value: unknown,
): asserts value is DocxCommentEdit {
  const change = record(value);
  let allowed: string[];
  if (
    change.action === "add" ||
    change.action === "addWord" ||
    change.action === "reply"
  ) {
    allowed = [
      "action",
      "text",
      "author",
      "initials",
      "date",
      change.action === "reply" ? "id" : "selection",
    ];
    if (
      !text(change.text, 32767, true) ||
      !text(change.author, 255, true) ||
      !text(change.initials, 32) ||
      Array.from(change.author + change.initials).some(
        (c) => c.codePointAt(0)! < 32,
      ) ||
      (change.action === "reply"
        ? !id(change.id)
        : !isDocxSelection(change.selection)) ||
      typeof change.date !== "string" ||
      !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{3})?Z$/u.test(
        change.date,
      ) ||
      change.date.startsWith("0000") ||
      !Number.isFinite(Date.parse(change.date)) ||
      new Date(change.date).toISOString() !==
        (change.date.length === 20
          ? change.date.replace("Z", ".000Z")
          : change.date)
    )
      throw new Error("Invalid comment creation");
    if (change.action === "addWord") {
      const selection = change.selection;
      if (
        !isDocxSelection(selection) ||
        selection.anchor.paragraph !== selection.focus.paragraph ||
        selection.anchor.offset !== selection.focus.offset
      )
        throw new Error("Word comments require a collapsed caret");
    }
  } else if (change.action === "resolve") {
    allowed = ["action", "id", "done"];
    if (!id(change.id) || typeof change.done !== "boolean")
      throw new Error("Invalid comment resolved state");
  } else if (change.action === "update") {
    allowed = ["action", "id", "text"];
    if (!id(change.id) || !text(change.text, 32767, true))
      throw new Error("Invalid comment update");
  } else if (change.action === "remove" || change.action === "goTo") {
    allowed = ["action", "id"];
    if (!id(change.id)) throw new Error("Invalid comment identity");
  } else throw new Error("Unknown comment command");
  if (
    Object.keys(change).length !== allowed.length ||
    Object.keys(change).some((key) => !allowed.includes(key))
  )
    throw new Error("Invalid comment fields");
}
export function docxComments(value: unknown): DocxComments {
  const result = record(value);
  if (
    !integer(result.revision, 0, 2147483647) ||
    !text(result.reason, 32767) ||
    !Array.isArray(result.items) ||
    result.items.length > 4096 ||
    (result.reason && result.items.length)
  )
    throw new Error("Invalid comments catalog");
  const seen = new Map<string, Record<string, unknown>>();
  let units = 0;
  for (const item of result.items) {
    const comment = record(item);
    if (
      !id(comment.id) ||
      seen.has(comment.id) ||
      !text(comment.text, 32767) ||
      !text(comment.author, 255) ||
      !text(comment.initials, 32) ||
      !text(comment.date, 128) ||
      !text(comment.reason, 32767) ||
      (comment.parent !== null && !id(comment.parent)) ||
      typeof comment.done !== "boolean" ||
      (comment.selection !== null && !isDocxSelection(comment.selection)) ||
      (!comment.reason && comment.selection === null)
    )
      throw new Error("Invalid local comment");
    units += comment.text.length;
    if (units > 1048576) throw new Error("Comments exceed text budget");
    seen.set(comment.id, comment);
  }
  for (const comment of seen.values()) {
    if (comment.parent === null) continue;
    const root = seen.get(String(comment.parent));
    if (!root || root.parent !== null || root.done !== comment.done)
      throw new Error("Invalid comment reply relationship");
  }
  return value as DocxComments;
}
