import { WasmSession } from "./session.js";
import { record } from "./validation.js";
import {
  checkPageSetup,
  checkPageBackground,
  checkPageBorders,
  docxPageSettings,
  editState,
  type DocxPageSetup,
  type DocxPageBorders,
} from "./docx-format.js";

export type DocxRunningVariant = "default" | "first" | "even";
export function checkRunningVariant(
  value: unknown,
): asserts value is DocxRunningVariant {
  if (value !== "default" && value !== "first" && value !== "even")
    throw new Error("Invalid running area variant");
}
export function checkRunningOptions(first: unknown, even: unknown): void {
  if (typeof first !== "boolean" || typeof even !== "boolean")
    throw new Error("Invalid running options");
}
export type DocxRunningKind = "header" | "footer";
export type DocxRunningContent =
  { text: string } | { field: "PAGE" | "NUMPAGES" };
export interface DocxRunningArea {
  revision: number;
  /** LF separates paragraphs; U+2028 is an inline soft break. */
  content: DocxRunningContent[];
  distance: number;
  reason: string;
  shared: boolean;
  differentFirst: boolean;
  differentEven: boolean;
}
export function checkRunningKind(
  kind: unknown,
): asserts kind is DocxRunningKind {
  if (kind !== "header" && kind !== "footer")
    throw new Error("Invalid running area kind");
}
export function checkRunningArea(
  kind: unknown,
  variant: unknown,
  content: unknown,
  distance: unknown,
): void {
  checkRunningKind(kind);
  checkRunningVariant(variant);
  if (!Array.isArray(content) || content.length > 256)
    throw new Error("Invalid running content");
  let units = 0;
  for (const value of content) {
    const item = record(value);
    if (Object.keys(item).length !== 1)
      throw new Error("Invalid running content item");
    if (typeof item.text === "string" && !/[\r\f]/u.test(item.text))
      units += item.text.length;
    else if (item.field === "PAGE" || item.field === "NUMPAGES") units++;
    else throw new Error("Invalid running content item");
  }
  if (
    units > 8192 ||
    typeof distance !== "number" ||
    !Number.isFinite(distance) ||
    distance < 0 ||
    distance > 14400 ||
    !Number.isInteger(distance * 20)
  )
    throw new Error("Invalid running content or distance");
}
export function docxRunningArea(value: unknown): DocxRunningArea {
  const area = record(value);
  checkRunningArea("header", "default", area.content, area.distance);
  checkRunningOptions(area.differentFirst, area.differentEven);
  if (
    !Number.isSafeInteger(area.revision) ||
    Number(area.revision) < 0 ||
    typeof area.reason !== "string" ||
    typeof area.shared !== "boolean" ||
    Object.keys(area).some(
      (key) =>
        ![
          "revision",
          "content",
          "distance",
          "reason",
          "shared",
          "differentFirst",
          "differentEven",
        ].includes(key),
    )
  )
    throw new Error("Invalid running area response");
  return value as DocxRunningArea;
}

/** Page commands share the session's revision and source transaction. */
export class FoundationPageSession extends WasmSession {
  unlinkRunningArea(
    revision: number,
    kind: DocxRunningKind,
    variant: DocxRunningVariant,
    profile: Record<string, string>,
  ) {
    checkRunningKind(kind);
    checkRunningVariant(variant);
    return editState(
      this.call({
        operation: "unlinkRunningArea",
        revision,
        kind,
        variant,
        profile,
      }),
    );
  }
  setRunningOptions(
    revision: number,
    first: boolean,
    even: boolean,
    profile: Record<string, string>,
  ) {
    checkRunningOptions(first, even);
    return editState(
      this.call({
        operation: "setRunningOptions",
        revision,
        first,
        even,
        profile,
      }),
    );
  }
  pageSetup(revision: number) {
    return docxPageSettings(this.call({ operation: "pageSetup", revision }));
  }
  setPageSetup(revision: number, page: DocxPageSetup) {
    checkPageSetup(page);
    return editState(this.call({ operation: "setPageSetup", revision, page }));
  }
  setPageBackground(revision: number, color: string | null) {
    checkPageBackground(color);
    return editState(
      this.call({ operation: "setPageBackground", revision, color }),
    );
  }
  setPageBorders(revision: number, borders: DocxPageBorders | null) {
    checkPageBorders(borders);
    return editState(
      this.call({ operation: "setPageBorders", revision, borders }),
    );
  }
  runningArea(
    revision: number,
    kind: DocxRunningKind,
    variant: DocxRunningVariant,
  ): DocxRunningArea {
    checkRunningKind(kind);
    checkRunningVariant(variant);
    return docxRunningArea(
      this.call({ operation: "runningArea", revision, kind, variant }),
    );
  }
  setRunningArea(
    revision: number,
    kind: DocxRunningKind,
    variant: DocxRunningVariant,
    content: DocxRunningContent[],
    distance: number,
    profile: Record<string, string>,
  ) {
    checkRunningArea(kind, variant, content, distance);
    return editState(
      this.call({
        operation: "setRunningArea",
        revision,
        kind,
        variant,
        content,
        distance,
        profile,
      }),
    );
  }
}
