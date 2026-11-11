import { record } from "@open-document/wasm/abi/validation";
import type { DocxSelection } from "./docx-hit.js";
import { isDocxSelection } from "./docx-search.js";

export type DocxBookmarkEdit =
  | { action: "create"; name: string; selection: DocxSelection }
  | { action: "rename"; name: string; replacement: string }
  | { action: "remove" | "goTo"; name: string };

export function checkDocxBookmark(change: DocxBookmarkEdit): void {
  const value = record(change);
  if (typeof value.name !== "string" || !value.name || value.name.length > 4096)
    throw new Error("Invalid bookmark name");
  const name = /^[A-Za-z_][A-Za-z0-9_]{0,39}$/;
  switch (value.action) {
    case "create":
      if (!name.test(value.name) || !isDocxSelection(value.selection))
        throw new Error("Invalid bookmark creation");
      break;
    case "rename":
      if (
        typeof value.replacement !== "string" ||
        !name.test(value.replacement)
      )
        throw new Error("Invalid bookmark name");
      break;
    case "remove":
    case "goTo":
      break;
    default:
      throw new Error("Invalid bookmark command");
  }
  const fields =
    value.action === "create"
      ? ["action", "name", "selection"]
      : value.action === "rename"
        ? ["action", "name", "replacement"]
        : ["action", "name"];
  if (
    Object.keys(value).length !== fields.length ||
    Object.keys(value).some((key) => !fields.includes(key))
  )
    throw new Error("Invalid bookmark fields");
}

export interface DocxOverview {
  revision: number;
  bookmarks: {
    name: string;
    selection: DocxSelection | null;
    reason: string;
  }[];
  headings: {
    paragraph: number;
    level: number;
    text: string;
    reason: string;
  }[];
  truncated: boolean;
  diagnostics: string[];
  /** Committed body text; Unicode scalar characters, whitespace-separated words. */
  statistics: {
    words: number;
    characters: number;
    charactersNoSpaces: number;
    paragraphs: number;
    reason: string;
  };
}
