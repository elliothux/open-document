import { record } from "@open-document/wasm/abi/validation";

export type PptxShowInkChange =
  | {
      action: "begin";
      color: string;
      width: number;
      points: { x: number; y: number }[];
    }
  | { action: "append" | "end"; points: { x: number; y: number }[] }
  | { action: "cancel" | "clear" };

export function checkPptxShowInk(value: unknown): void {
  const change = record(value);
  const keys =
    change.action === "begin"
      ? ["action", "color", "width", "points"]
      : change.action === "append" || change.action === "end"
        ? ["action", "points"]
        : change.action === "cancel" || change.action === "clear"
          ? ["action"]
          : [];
  if (
    !keys.length ||
    Object.keys(change).length !== keys.length ||
    Object.keys(change).some((key) => !keys.includes(key))
  )
    throw new Error("Invalid slideshow ink fields");
  if (keys.includes("points")) {
    if (
      !Array.isArray(change.points) ||
      change.points.length > 64 ||
      (change.action !== "end" && !change.points.length)
    )
      throw new Error("Invalid ink point batch");
    for (const value of change.points) {
      const point = record(value);
      if (
        Object.keys(point).length !== 2 ||
        ![point.x, point.y].every(
          (value) =>
            typeof value === "number" &&
            Number.isFinite(value) &&
            value >= 0 &&
            value <= 14400,
        )
      )
        throw new Error("Invalid ink point");
    }
  }
  if (
    change.action === "begin" &&
    (typeof change.color !== "string" ||
      !/^[0-9a-fA-F]{6}$/.test(change.color) ||
      typeof change.width !== "number" ||
      !Number.isFinite(change.width) ||
      change.width < 0.5 ||
      change.width > 24)
  )
    throw new Error("Invalid ink color or width");
}
