import { record } from "./validation.js";
import { checkGradientStops, type GradientStop } from "./drawing.js";
import { imageInsets } from "./pptx-objects.js";

export type PptxBackgroundFill =
  | { kind: "solid"; color: string }
  | { kind: "radial"; stops: GradientStop[] }
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
  if (fill.kind === "linear" || fill.kind === "radial")
    checkGradientStops(fill.stops);
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
        typeof fill.scaled === "boolean") ||
      fill.kind === "radial"
    ) ||
    Object.keys(fill).some(
      (key) =>
        !(
          fill.kind === "solid"
            ? ["kind", "color"]
            : fill.kind === "radial"
              ? ["kind", "stops"]
              : ["kind", "stops", "angle", "scaled"]
        ).includes(key),
    )
  )
    throw new Error("Invalid slide background fill");
}

export function checkPptxShapeGradient(change: Record<string, unknown>): void {
  const linear = change.action === "gradientFill";
  const fields = linear
    ? ["action", "stops", "angle", "scaled"]
    : ["action", "stops"];
  if (Object.keys(change).some((key) => !fields.includes(key)))
    throw new Error("Invalid shape gradient fields");
  checkPptxBackgroundFill(
    linear
      ? {
          kind: "linear",
          stops: change.stops,
          angle: change.angle,
          scaled: change.scaled,
        }
      : { kind: "radial", stops: change.stops },
  );
}
