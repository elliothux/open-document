import { record } from "@open-document/wasm/abi/validation";
import {
  xlsxDrawingDescriptionUnits,
  xlsxDrawingNameUnits,
  xlsxShapeFontUnits,
  xlsxShapeTextUnits,
} from "@open-document/wasm/engine-source";

export const xlsxShapeKinds = ["rect", "ellipse", "line", "textBox"] as const;
export type XlsxShapeKind = (typeof xlsxShapeKinds)[number];
export interface XlsxShapeSettings {
  kind: XlsxShapeKind;
  anchor: "fixed" | "move" | "size";
  x: number;
  y: number;
  width: number;
  height: number;
  name: string;
  description: string;
  fill: string | null;
  stroke: string | null;
  lineWidth: number;
  text: string;
  font: string;
  bold: boolean;
  italic: boolean;
  size: number;
  color: string;
  wrap: boolean;
  align: "left" | "center" | "right";
  vertical: "top" | "center" | "bottom";
  insets: { left: number; top: number; right: number; bottom: number };
}
export interface XlsxShape extends XlsxShapeSettings {
  id: string;
}
export interface XlsxShapes {
  revision: number;
  sheet: string;
  reason: string;
  items: XlsxShape[];
}

function finite(value: unknown, min: number, max: number): value is number {
  return (
    typeof value === "number" &&
    Number.isFinite(value) &&
    value >= min &&
    value <= max
  );
}
function kind(value: unknown): value is XlsxShapeKind {
  return (
    typeof value === "string" && xlsxShapeKinds.some((kind) => kind === value)
  );
}
function color(value: unknown): boolean {
  return typeof value === "string" && /^[0-9a-f]{6}$/i.test(value);
}
function dimensions(
  k: unknown,
  width: unknown,
  height: unknown,
  editable: boolean,
): boolean {
  return (
    kind(k) &&
    finite(width, 0, 14400) &&
    finite(height, 0, 14400) &&
    (!editable ||
      (k === "line"
        ? width >= 0.1 || height >= 0.1
        : width >= 0.1 && height >= 0.1))
  );
}
export function checkXlsxShapeInsert(
  kind: unknown,
  width: unknown,
  height: unknown,
  text: unknown,
): void {
  if (
    !dimensions(kind, width, height, true) ||
    typeof text !== "string" ||
    text.length > xlsxShapeTextUnits ||
    (kind === "line" && text !== "")
  )
    throw new Error("Invalid worksheet shape insertion");
}
function settings(value: unknown, editable: boolean): void {
  const p = record(value);
  const insets = record(p.insets);
  if (
    !dimensions(p.kind, p.width, p.height, editable) ||
    typeof p.anchor !== "string" ||
    !["fixed", "move", "size"].includes(p.anchor) ||
    !finite(p.x, 0, 1e9) ||
    !finite(p.y, 0, 1e9) ||
    typeof p.name !== "string" ||
    !p.name.trim() ||
    p.name.length > xlsxDrawingNameUnits ||
    typeof p.description !== "string" ||
    p.description.length > xlsxDrawingDescriptionUnits ||
    (p.fill !== null && !color(p.fill)) ||
    (p.stroke !== null && !color(p.stroke)) ||
    !finite(p.lineWidth, 0, 1000) ||
    typeof p.text !== "string" ||
    p.text.length > xlsxShapeTextUnits ||
    (p.kind === "line" && p.text !== "") ||
    typeof p.font !== "string" ||
    !p.font.trim() ||
    p.font.length > xlsxShapeFontUnits ||
    typeof p.bold !== "boolean" ||
    typeof p.italic !== "boolean" ||
    !finite(p.size, 1, 400) ||
    !color(p.color) ||
    typeof p.wrap !== "boolean" ||
    typeof p.align !== "string" ||
    !["left", "center", "right"].includes(p.align) ||
    typeof p.vertical !== "string" ||
    !["top", "center", "bottom"].includes(p.vertical) ||
    !["left", "top", "right", "bottom"].every((key) =>
      finite(insets[key], 0, 14400),
    )
  )
    throw new Error("Invalid worksheet shape settings");
}
export function checkXlsxShapeSettings(
  value: unknown,
): asserts value is XlsxShapeSettings {
  settings(value, true);
}
