import type { DocxSelection } from "./docx-hit.js";
import { isDocxSelection } from "./docx-search.js";
import { integer, record } from "@open-document/wasm/abi/validation";
import { docxCommentTextUnits } from "@open-document/wasm/engine-source";
import { type EditState } from "./docx-format.js";

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
      !text(change.text, docxCommentTextUnits, true) ||
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
    if (!id(change.id) || !text(change.text, docxCommentTextUnits, true))
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
