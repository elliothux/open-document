import { record } from "./validation.js";
import { checkGradientStops, type GradientStop } from "./drawing.js";
import { imageInsets } from "./pptx-objects.js";

export type PptxBackgroundFill =
  | { kind: "solid"; color: string }
  | {
      kind: "linear";
      stops: GradientStop[];
      angle: number;
      scaled: boolean;
    };

export type PptxBackground =
  | PptxBackgroundFill
  | {
      kind: "image";
      key: string;
      crop: [number, number, number, number];
      insets: [number, number, number, number];
      opacity: number;
      mode: "stretch" | "tile";
    };

export function checkPptxBackground(value: unknown): void {
  const fill = record(value);
  if (fill.kind !== "image") {
    checkPptxBackgroundFill(value);
    return;
  }
  checkBackgroundImageFormat(fill);
  imageInsets(fill.insets);
  if (
    typeof fill.key !== "string" ||
    !fill.key ||
    fill.key.length > 256 ||
    !fill.key.isWellFormed() ||
    Object.keys(fill).some(
      (key) =>
        !["kind", "key", "crop", "insets", "opacity", "mode"].includes(key),
    )
  )
    throw new Error("Invalid picture background");
}

export function checkBackgroundImageFormat(
  fill: Record<string, unknown>,
): void {
  if (
    typeof fill.opacity !== "number" ||
    !Number.isFinite(fill.opacity) ||
    fill.opacity < 0 ||
    fill.opacity > 1 ||
    (fill.mode !== "stretch" && fill.mode !== "tile") ||
    !Array.isArray(fill.crop) ||
    fill.crop.length !== 4 ||
    fill.crop.some(
      (v) => typeof v !== "number" || !Number.isFinite(v) || v < 0 || v >= 1,
    ) ||
    fill.crop[0] + fill.crop[2] >= 1 ||
    fill.crop[1] + fill.crop[3] >= 1
  )
    throw new Error("Invalid picture background");
}

export function checkPptxBackgroundFill(value: unknown): void {
  const fill = record(value);
  if (fill.kind === "linear") checkGradientStops(fill.stops);
  if (
    !(
      (fill.kind === "solid" &&
        typeof fill.color === "string" &&
        /^[0-9a-f]{6}$/iu.test(fill.color)) ||
      (fill.kind === "linear" &&
        typeof fill.angle === "number" &&
        Number.isFinite(fill.angle) &&
        fill.angle >= 0 &&
        fill.angle <= 360 &&
        typeof fill.scaled === "boolean")
    ) ||
    Object.keys(fill).some(
      (key) =>
        !(
          fill.kind === "solid"
            ? ["kind", "color"]
            : ["kind", "stops", "angle", "scaled"]
        ).includes(key),
    )
  )
    throw new Error("Invalid slide background fill");
}
