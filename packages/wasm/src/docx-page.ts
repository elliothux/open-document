import { FoundationReviewSession } from "./docx-revisions.js";
import {
  docxRuler,
  checkDocxRulerEdit,
  type DocxRuler,
  type DocxRulerEdit,
} from "./docx-ruler.js";
import { record } from "./validation.js";

export interface DocxCoverPage {
  title: string;
  subtitle: string;
}
const singleLineText = (value: unknown, max: number): value is string =>
  typeof value === "string" &&
  value.length <= max &&
  value.isWellFormed() &&
  Array.from(value).every((c) => {
    const n = c.codePointAt(0)!;
    return (
      n >= 32 &&
      n !== 127 &&
      n !== 8232 &&
      n !== 8233 &&
      n !== 65534 &&
      n !== 65535
    );
  });
export function checkDocxCoverPage(
  value: unknown,
): asserts value is DocxCoverPage | null {
  if (value === null) return;
  const cover = record(value);
  if (
    Object.keys(cover).length !== 2 ||
    Object.keys(cover).some((key) => key !== "title" && key !== "subtitle") ||
    !singleLineText(cover.title, 256) ||
    !cover.title.trim() ||
    !singleLineText(cover.subtitle, 512)
  )
    throw new Error("Invalid cover page title or subtitle");
}
import { checkDocxHyperlink } from "./docx-format.js";
import { docxProtection, checkDocxProtection } from "./docx-protection.js";
import { protectionSalt } from "./protection-password.js";
import { isDocxSelection } from "./docx-search.js";
import type { DocxSelection } from "./docx-hit.js";
import {
  checkPageSetup,
  checkPageBackground,
  checkPageBorders,
  checkPageNumbering,
  checkDocxColumns,
  docxPageSettings,
  editState,
  type DocxPageSetup,
  type DocxPageBorders,
  type DocxPageNumbering,
  type DocxColumns,
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
export type DocxPageField = {
  field: "PAGE" | "NUMPAGES";
  format?: Exclude<DocxPageNumbering["format"], "decimalZero">;
};
export interface DocxCaption {
  label: string;
  text: string;
  position: "before" | "after";
  format?: DocxPageField["format"];
}
export function checkDocxCaption(value: unknown): asserts value is DocxCaption {
  const caption = record(value);
  if (
    Object.keys(caption).some(
      (key) => !["label", "text", "position", "format"].includes(key),
    ) ||
    !singleLineText(caption.text, 1024) ||
    (caption.position !== "before" && caption.position !== "after")
  )
    throw new Error("Invalid caption text or position");
  checkBodyField({
    field: "SEQ",
    sequence: caption.label,
    ...("format" in caption ? { format: caption.format } : {}),
  });
}
export type DocxRunningContent =
  { text: string; target?: string } | DocxPageField;
export type DocxBodyField =
  | DocxPageField
  | {
      field: "SEQ";
      sequence: string;
      format?: DocxPageField["format"];
      restart?: number;
      repeat?: boolean;
      headingLevel?: number;
      hidden?: boolean;
    }
  | { field: "REF"; bookmark: string; hyperlink?: boolean }
  | {
      field: "PAGEREF";
      bookmark: string;
      format?: Exclude<DocxPageField["format"], undefined>;
      hyperlink?: boolean;
      relative?: boolean;
    };
export interface DocxBodyPageField {
  revision: number;
  selection: DocxSelection;
  field: DocxBodyField | null;
  reason: string;
}
export function docxBodyPageField(value: unknown): DocxBodyPageField {
  const result = record(value);
  if (
    !Number.isSafeInteger(result.revision) ||
    Number(result.revision) < 0 ||
    !isDocxSelection(result.selection) ||
    typeof result.reason !== "string" ||
    Object.keys(result).length !== 4 ||
    Object.keys(result).some(
      (key) => !["revision", "selection", "field", "reason"].includes(key),
    )
  )
    throw new Error("Invalid body page field response");
  if (result.field !== null) checkBodyField(result.field);
  if ((result.field === null) !== result.reason.length > 0)
    throw new Error("Invalid body page field availability");
  return value as DocxBodyPageField;
}
export function checkPageField(value: unknown): asserts value is DocxPageField {
  const item = record(value);
  if (item.field !== "PAGE" && item.field !== "NUMPAGES")
    throw new Error("Invalid body page field");
  checkRunningArea("header", "default", [value], 0);
}
export function checkBodyField(value: unknown): asserts value is DocxBodyField {
  const item = record(value);
  if (item.field === "SEQ") {
    if (
      typeof item.sequence !== "string" ||
      item.sequence.length > 40 ||
      !/^[_\p{ID_Start}][_\p{ID_Continue}]*$/u.test(item.sequence) ||
      Object.keys(item).some(
        (key) =>
          ![
            "field",
            "sequence",
            "format",
            "restart",
            "repeat",
            "headingLevel",
            "hidden",
          ].includes(key),
      ) ||
      ("repeat" in item && typeof item.repeat !== "boolean") ||
      ("hidden" in item && typeof item.hidden !== "boolean") ||
      (item.hidden === true && "format" in item) ||
      ("headingLevel" in item &&
        (!Number.isInteger(item.headingLevel) ||
          Number(item.headingLevel) < 1 ||
          Number(item.headingLevel) > 9)) ||
      ("restart" in item &&
        (!Number.isInteger(item.restart) ||
          Number(item.restart) < 0 ||
          Number(item.restart) > 2147483647 ||
          item.repeat === true))
    )
      throw new Error("Invalid sequence field identifier");
    checkPageField(
      "format" in item
        ? { field: "PAGE", format: item.format }
        : { field: "PAGE" },
    );
    return;
  }
  if (item.field !== "PAGEREF" && item.field !== "REF")
    return checkPageField(value);
  const textReference = item.field === "REF";
  if (
    typeof item.bookmark !== "string" ||
    !/^[A-Za-z_][A-Za-z0-9_]{0,39}$/u.test(item.bookmark) ||
    Object.keys(item).some(
      (key) =>
        !(
          textReference
            ? ["field", "bookmark", "hyperlink"]
            : ["field", "bookmark", "format", "hyperlink", "relative"]
        ).includes(key),
    ) ||
    ("hyperlink" in item && typeof item.hyperlink !== "boolean") ||
    ("relative" in item && typeof item.relative !== "boolean")
  )
    throw new Error("Invalid page reference target");
  if (!textReference)
    checkPageField(
      "format" in item
        ? { field: "PAGE", format: item.format }
        : { field: "PAGE" },
    );
}
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
    if (
      Object.keys(item).every((key) => key === "text" || key === "target") &&
      typeof item.text === "string" &&
      !/[\r\f\v]/u.test(item.text)
    ) {
      if ("target" in item) {
        if (typeof item.target !== "string" || !item.text)
          throw new Error("Invalid running link");
        checkDocxHyperlink(item.target);
      }
      units += item.text.length;
    } else if (
      (item.field === "PAGE" || item.field === "NUMPAGES") &&
      Object.keys(item).every((key) => ["field", "format"].includes(key))
    ) {
      if ("format" in item) {
        checkPageNumbering({ start: 1, format: item.format });
        if (item.format === "decimalZero")
          throw new Error("Invalid explicit running field format");
      }
      units++;
    } else throw new Error("Invalid running content item");
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
export class FoundationPageSession extends FoundationReviewSession {
  documentProtection(revision: number) {
    return docxProtection(
      this.call({ operation: "documentProtection", revision }),
    );
  }
  setDocumentProtection(revision: number, enabled: boolean, password: string) {
    checkDocxProtection(enabled, password);
    return editState(
      this.call({
        operation: "setDocumentProtection",
        revision,
        enabled,
        password,
        passwordSalt: protectionSalt(enabled, password),
      }),
    );
  }
  bodyPageField(revision: number, selection: DocxSelection): DocxBodyPageField {
    return docxBodyPageField(
      this.call({ operation: "bodyPageField", revision, selection }),
    );
  }
  editBodyPageField(
    revision: number,
    selection: DocxSelection,
    field: DocxBodyField,
    profile: Record<string, string>,
  ) {
    checkBodyField(field);
    return editState(
      this.call({
        operation: "editBodyPageField",
        revision,
        selection,
        field,
        profile,
      }),
    );
  }
  insertBodyPageField(
    revision: number,
    field: DocxBodyField,
    profile: Record<string, string>,
  ) {
    checkBodyField(field);
    return editState(
      this.call({ operation: "insertBodyPageField", revision, field, profile }),
    );
  }
  insertCaption(
    revision: number,
    caption: DocxCaption,
    profile: Record<string, string>,
  ) {
    checkDocxCaption(caption);
    return editState(
      this.call({ operation: "insertDocxCaption", revision, caption, profile }),
    );
  }
  ruler(revision: number): DocxRuler {
    return docxRuler(this.call({ operation: "docxRuler", revision }));
  }
  editRuler(source: DocxRuler, change: DocxRulerEdit) {
    docxRuler(source);
    checkDocxRulerEdit(change);
    return editState(
      this.call({
        operation: "editDocxRuler",
        revision: source.revision,
        layoutId: source.layoutId,
        selection: source.selection,
        change,
      }),
    );
  }
  setPageNumbering(
    revision: number,
    numbering: DocxPageNumbering | null,
    profile: Record<string, string>,
  ) {
    checkPageNumbering(numbering);
    return editState(
      this.call({
        operation: "setPageNumbering",
        revision,
        numbering,
        profile,
      }),
    );
  }
  updateBodyPageFields(revision: number, profile: Record<string, string>) {
    return editState(
      this.call({ operation: "updateBodyPageFields", revision, profile }),
    );
  }
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
  setPageColumns(
    revision: number,
    columns: DocxColumns | null,
    profile: Record<string, string>,
  ) {
    checkDocxColumns(columns);
    return editState(
      this.call({ operation: "setPageColumns", revision, columns, profile }),
    );
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
  setCoverPage(
    revision: number,
    cover: DocxCoverPage | null,
    profile: Record<string, string>,
  ) {
    checkDocxCoverPage(cover);
    return editState(
      this.call({ operation: "setCoverPage", revision, cover, profile }),
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
