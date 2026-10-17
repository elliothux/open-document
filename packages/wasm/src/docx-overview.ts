import { integer, record } from "./validation.js";
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

export function docxOverview(value: unknown): DocxOverview {
  const result = record(value),
    stats = record(result.statistics);
  if (
    !integer(result.revision, 0, 2147483647) ||
    !Array.isArray(result.bookmarks) ||
    result.bookmarks.length > 4096 ||
    typeof result.truncated !== "boolean" ||
    !Array.isArray(result.headings) ||
    result.headings.length > 4096 ||
    !Array.isArray(result.diagnostics) ||
    result.diagnostics.length > 4096 ||
    !result.diagnostics.every(
      (v) => typeof v === "string" && v.length <= 8192,
    ) ||
    typeof stats.reason !== "string" ||
    ![
      stats.words,
      stats.characters,
      stats.charactersNoSpaces,
      stats.paragraphs,
    ].every((v) => integer(v, 0, 1048576)) ||
    Number(stats.charactersNoSpaces) > Number(stats.characters) ||
    Number(stats.words) > Number(stats.charactersNoSpaces) ||
    Number(stats.paragraphs) > Number(stats.words)
  )
    throw new Error("Invalid DOCX overview");
  for (const item of result.bookmarks) {
    const bookmark = record(item);
    if (
      typeof bookmark.name !== "string" ||
      typeof bookmark.reason !== "string" ||
      (bookmark.selection !== null && !isDocxSelection(bookmark.selection)) ||
      (!bookmark.reason && (!bookmark.name || bookmark.selection === null))
    )
      throw new Error("Invalid DOCX bookmark");
  }
  const seen = new Set<number>();
  for (const value of result.headings) {
    const heading = record(value);
    if (
      !integer(heading.paragraph, 0, 2147483647) ||
      seen.has(Number(heading.paragraph)) ||
      !integer(heading.level, 1, 9) ||
      typeof heading.text !== "string" ||
      !heading.text ||
      heading.text.length > 256 ||
      !heading.text.isWellFormed() ||
      typeof heading.reason !== "string"
    )
      throw new Error("Invalid DOCX heading");
    seen.add(Number(heading.paragraph));
  }
  return value as DocxOverview;
}
