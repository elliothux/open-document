import { record, integer } from "./validation.js";
import { FoundationMathSession } from "./docx-math.js";
import { editState } from "./docx-format.js";
import { drawingBatch } from "./drawing.js";

export interface DocxInkStroke {
  points: [number, number][];
  color: string;
  width: number;
  highlighter: boolean;
}

export interface DocxInkTool {
  tool: "select" | "pen" | "highlighter" | "eraser";
  color: string;
  width: number;
}

export function checkInkTool(value: unknown): asserts value is DocxInkTool {
  const options = record(value);
  if (
    Object.keys(options).length !== 3 ||
    typeof options.tool !== "string" ||
    !["select", "pen", "highlighter", "eraser"].includes(
      String(options.tool),
    ) ||
    typeof options.color !== "string" ||
    !/^[0-9a-f]{6}$/i.test(options.color) ||
    typeof options.width !== "number" ||
    !Number.isFinite(options.width) ||
    options.width < 0.5 ||
    options.width > 24
  )
    throw new Error("Invalid document ink tool");
}

export function checkInkTarget(
  revision: number,
  layoutId: number,
  page: number,
): void {
  if (
    !integer(revision, 0, 2147483647) ||
    !integer(layoutId, 0, 2147483647) ||
    !integer(page, 0, 1023)
  )
    throw new Error("Invalid ink layout target");
}

export function checkInkPoint(x: unknown, y: unknown): void {
  if (
    ![x, y].every(
      (value) =>
        typeof value === "number" &&
        Number.isFinite(value) &&
        value >= 0 &&
        value <= 14400,
    )
  )
    throw new Error("Invalid ink coordinate");
}

export function checkInkStroke(value: unknown): asserts value is DocxInkStroke {
  const stroke = record(value);
  if (
    Object.keys(stroke).length !== 4 ||
    typeof stroke.color !== "string" ||
    !/^[0-9a-f]{6}$/i.test(stroke.color) ||
    typeof stroke.width !== "number" ||
    !Number.isFinite(stroke.width) ||
    stroke.width < 0.5 ||
    stroke.width > 24 ||
    typeof stroke.highlighter !== "boolean" ||
    !Array.isArray(stroke.points) ||
    stroke.points.length < 1 ||
    stroke.points.length > 4096
  )
    throw new Error("Invalid ink stroke");
  for (const point of stroke.points) {
    if (!Array.isArray(point) || point.length !== 2)
      throw new Error("Invalid ink sample");
    checkInkPoint(point[0], point[1]);
  }
}

export class FoundationInkSession extends FoundationMathSession {
  previewInk(
    revision: number,
    layoutId: number,
    page: number,
    stroke: DocxInkStroke,
  ) {
    checkInkTarget(revision, layoutId, page);
    checkInkStroke(stroke);
    return drawingBatch(
      this.call({
        operation: "docxInk",
        action: "preview",
        revision,
        layoutId,
        page,
        stroke,
      }),
    );
  }
  insertInk(
    revision: number,
    layoutId: number,
    page: number,
    stroke: DocxInkStroke,
    profile: Record<string, string> = {},
  ) {
    checkInkTarget(revision, layoutId, page);
    checkInkStroke(stroke);
    return editState(
      this.call({
        operation: "docxInk",
        action: "insert",
        revision,
        layoutId,
        page,
        stroke,
        profile,
      }),
    );
  }
  eraseInk(
    revision: number,
    layoutId: number,
    page: number,
    x: number,
    y: number,
  ) {
    checkInkTarget(revision, layoutId, page);
    checkInkPoint(x, y);
    return editState(
      this.call({
        operation: "docxInk",
        action: "erase",
        revision,
        layoutId,
        page,
        x,
        y,
      }),
    );
  }
}
