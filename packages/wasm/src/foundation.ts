import {
  docxFlow,
  pageLayout,
  type DocxFlow,
  type PageLayout,
} from "./preview.js";
import { record, hasFields, arrayOf, glyphs } from "./validation.js";

export interface Budget {
  fileBytes: number;
  entryBytes: number;
  totalBytes: number;
  retainedBytes: number;
  entries: number;
  xmlDepth: number;
  outputBytes: number;
}

export interface DocxQuery {
  revision: number;
  mainPart: string;
  texts: { id: number; paragraph: number; run: number; text: string }[];
  relationships: {
    owner: string;
    id: string;
    type: string;
    target: string;
    external: boolean;
  }[];
  diagnostics: string[];
  decodedBytes: number;
}

export interface ShapeBatch {
  text: string;
  glyphs: {
    id: number;
    cluster: number;
    font: number;
    outline: string;
    x: number;
    y: number;
    scale: number;
    advance: number;
    yAdvance: number;
    xOffset: number;
    yOffset: number;
  }[];
  outlines: { key: string; path: string }[];
  runs: {
    start: number;
    end: number;
    level: number;
    font: number;
    script: string;
    language: string;
  }[];
  fonts: {
    identity: string;
    sha256: string;
    face: number;
    variation: string;
    upem: number;
    ascent: number;
    descent: number;
    bbox: number[];
    capHeight: number;
    italicAngle: number;
  }[];
  diagnostics: { code: string; cluster: number; codepoint: number }[];
  width: number;
  fontBytes: number;
  outlineBytes: number;
}

export class DocumentError extends Error {
  constructor(
    readonly code: string,
    message: string,
    readonly part: string,
    readonly offset: number,
  ) {
    super(message);
    this.name = "DocumentError";
  }
}

export function docxQuery(value: unknown): DocxQuery {
  const object = record(value);
  if (
    !hasFields(value, ["mainPart"], ["revision", "decodedBytes"]) ||
    !arrayOf(object.texts, (entry) =>
      hasFields(entry, ["text"], ["id", "paragraph", "run"]),
    ) ||
    !arrayOf(
      object.relationships,
      (entry) =>
        hasFields(entry, ["owner", "id", "type", "target"], []) &&
        typeof record(entry).external === "boolean",
    ) ||
    !arrayOf(object.diagnostics, (entry) => typeof entry === "string")
  )
    throw new Error("Invalid DOCX query returned by Wasm");
  return value as DocxQuery;
}

export function resourceBudget(value: unknown): Budget {
  if (
    !hasFields(
      value,
      [],
      [
        "fileBytes",
        "entryBytes",
        "totalBytes",
        "retainedBytes",
        "entries",
        "xmlDepth",
        "outputBytes",
      ],
    )
  )
    throw new Error("Invalid resource budget returned by Wasm");
  return value as Budget;
}

export function shapeBatch(value: unknown): ShapeBatch {
  const object = record(value);
  if (
    !hasFields(value, ["text"], ["width", "fontBytes", "outlineBytes"]) ||
    !glyphs(object.glyphs) ||
    !arrayOf(object.outlines, (entry) =>
      hasFields(entry, ["key", "path"], []),
    ) ||
    !arrayOf(object.runs, (entry) =>
      hasFields(
        entry,
        ["script", "language"],
        ["start", "end", "level", "font"],
      ),
    ) ||
    !arrayOf(
      object.fonts,
      (entry) =>
        hasFields(
          entry,
          ["identity", "variation", "sha256"],
          ["face", "upem", "ascent", "descent", "capHeight", "italicAngle"],
        ) &&
        arrayOf(
          record(entry).bbox,
          (value) => typeof value === "number" && Number.isFinite(value),
        ),
    ) ||
    !arrayOf(object.diagnostics, (entry) =>
      hasFields(entry, ["code"], ["cluster", "codepoint"]),
    )
  )
    throw new Error("Invalid shape batch returned by Wasm");
  return value as ShapeBatch;
}

function encodeBytes(bytes: Uint8Array): string {
  let binary = "";
  for (let start = 0; start < bytes.length; start += 32768)
    binary += String.fromCharCode(...bytes.subarray(start, start + 32768));
  return btoa(binary);
}

export class FoundationSession {
  private closed = false;

  constructor(
    private readonly exports: WebAssembly.Exports,
    private readonly handle: unknown,
  ) {}

  private call(request: object): unknown {
    if (this.closed) throw new Error("Session is closed");
    const fn = this.exports.foundation_call;
    if (typeof fn !== "function")
      throw new Error("Missing foundation_call export");
    const output: unknown = fn(this.handle, JSON.stringify(request));
    if (typeof output !== "string") throw new Error("Invalid Wasm response");
    const result = record(JSON.parse(output));
    if (result.ok === true) return result.value;
    const error = record(result.error);
    if (
      result.ok !== false ||
      !hasFields(error, ["code", "message", "part"], ["offset"])
    )
      throw new Error("Invalid Wasm error");
    if (
      typeof error.code === "string" &&
      typeof error.message === "string" &&
      typeof error.part === "string" &&
      typeof error.offset === "number"
    )
      throw new DocumentError(
        error.code,
        error.message,
        error.part,
        error.offset,
      );
    throw new Error("Invalid Wasm error");
  }

  addFont(bytes: Uint8Array, identity: string): void {
    if (bytes.length > 33554432)
      throw new DocumentError(
        "limit-exceeded",
        "Font input exceeds budget",
        "",
        -1,
      );
    this.call({ operation: "font", bytes: encodeBytes(bytes), identity });
  }

  defaultBudget(): Budget {
    return resourceBudget(this.call({ operation: "budget" }));
  }

  shape(text: string, size = 32, language = "und"): ShapeBatch {
    return shapeBatch(this.call({ operation: "shape", text, size, language }));
  }

  openDocx(bytes: Uint8Array, budget: Budget): DocxQuery {
    if (bytes.length > budget.fileBytes || bytes.length > budget.retainedBytes)
      throw new DocumentError(
        "limit-exceeded",
        "Byte input exceeds budget",
        "",
        -1,
      );
    return docxQuery(
      this.call({ operation: "openDocx", bytes: encodeBytes(bytes), budget }),
    );
  }

  query(): DocxQuery {
    return docxQuery(this.call({ operation: "query" }));
  }

  replaceNode(node: number, revision: number, text: string): number {
    const result = record(
      this.call({ operation: "replaceNode", node, revision, text }),
    );
    if (typeof result.revision !== "number")
      throw new Error("Invalid revision");
    return result.revision;
  }

  saveDocx(): Uint8Array {
    return this.bytes({ operation: "saveDocx" });
  }

  flow(): DocxFlow {
    return docxFlow(this.call({ operation: "flow" }));
  }

  layout(profile: Record<string, string>): PageLayout {
    return pageLayout(this.call({ operation: "layout", profile }));
  }

  exportPdf(outputBytes: number, layoutId?: number): Uint8Array {
    return this.bytes({ operation: "exportPdf", outputBytes, layoutId });
  }

  imageBytes(key: string): Uint8Array {
    return this.bytes({ operation: "imageBytes", key });
  }

  addImage(key: string, width: number, height: number, rgba: Uint8Array): void {
    this.call({
      operation: "image",
      key,
      width,
      height,
      bytes: encodeBytes(rgba),
    });
  }

  private bytes(request: Record<string, unknown>): Uint8Array {
    const result = record(this.call(request));
    if (typeof result.bytes !== "string")
      throw new Error("Invalid saved bytes");
    return Uint8Array.from(atob(result.bytes), (char) => char.charCodeAt(0));
  }

  close(): void {
    if (this.closed) return;
    const fn = this.exports.foundation_close;
    if (typeof fn !== "function")
      throw new Error("Missing foundation_close export");
    fn(this.handle);
    this.closed = true;
  }
}
