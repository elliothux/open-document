import { record } from "./validation.js";

export interface BasicDrawingShape {
  preset: "rect" | "ellipse" | "line" | "polyline";
  fill: string;
  stroke: string;
  lineWidth: number;
  points: [number, number][];
  strokeAlpha: number;
}

export function checkShapePath(value: unknown): void {
  const shape = record(value);
  if (
    typeof shape.strokeAlpha !== "number" ||
    !Number.isFinite(shape.strokeAlpha) ||
    shape.strokeAlpha < 0 ||
    shape.strokeAlpha > 1 ||
    !Array.isArray(shape.points) ||
    shape.points.length > 4096 ||
    (shape.preset === "polyline"
      ? shape.points.length < 2 ||
        shape.fill !== "" ||
        shape.stroke === "" ||
        Number(shape.lineWidth) <= 0
      : shape.points.length !== 0 || shape.strokeAlpha !== 1) ||
    !shape.points.every(
      (point: unknown) =>
        Array.isArray(point) &&
        point.length === 2 &&
        point.every(
          (coordinate: unknown) =>
            typeof coordinate === "number" &&
            Number.isFinite(coordinate) &&
            coordinate >= 0 &&
            coordinate <= 1,
        ),
    )
  )
    throw new Error("Invalid drawing shape path");
}
