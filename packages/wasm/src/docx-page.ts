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
export interface DocxRunningArea {
  revision: number;
  /** LF separates paragraphs; U+2028 is an inline soft break. */
  text: string;
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
  text: unknown,
  distance: unknown,
): void {
  checkRunningKind(kind);
  checkRunningVariant(variant);
  if (
    typeof text !== "string" ||
    text.length > 8192 ||
    /[\r\f]/u.test(text) ||
    typeof distance !== "number" ||
    !Number.isFinite(distance) ||
    distance < 0 ||
    distance > 14400 ||
    !Number.isInteger(distance * 20)
  )
    throw new Error("Invalid running area text or distance");
}
export function docxRunningArea(value: unknown): DocxRunningArea {
  const area = record(value);
  checkRunningArea("header", "default", area.text, area.distance);
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
          "text",
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
    text: string,
    distance: number,
    profile: Record<string, string>,
  ) {
    checkRunningArea(kind, variant, text, distance);
    return editState(
      this.call({
        operation: "setRunningArea",
        revision,
        kind,
        variant,
        text,
        distance,
        profile,
      }),
    );
  }
}
