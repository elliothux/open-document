import { record } from "./validation.js";

/** One-off paper/margins; saved worksheet scaling still applies. */
export interface PrintOptions {
  width: number;
  height: number;
  top: number;
  right: number;
  bottom: number;
  left: number;
  range?: string;
}
export interface XlsxPrintSetup {
  paper: "A4" | "Letter";
  orientation: "portrait" | "landscape";
  left: number;
  top: number;
  right: number;
  bottom: number;
  scale: number;
  fitWidth: number;
  fitHeight: number;
}
function finite(value: unknown, low: number, high: number): value is number {
  return (
    typeof value === "number" &&
    Number.isFinite(value) &&
    value >= low &&
    value <= high
  );
}
export function checkXlsxPrintSetup(value: unknown): void {
  const setup = record(value);
  if (
    !["A4", "Letter"].includes(String(setup.paper)) ||
    !["portrait", "landscape"].includes(String(setup.orientation)) ||
    !["left", "top", "right", "bottom"].every((key) =>
      finite(setup[key], 0, 14400),
    ) ||
    !finite(setup.scale, 10, 400) ||
    !Number.isInteger(setup.scale) ||
    ![setup.fitWidth, setup.fitHeight].every(
      (value) => finite(value, 0, 1024) && Number.isInteger(value),
    )
  )
    throw new Error("Invalid worksheet print setup");
}
export function xlsxPrintSetup(
  value: unknown,
): XlsxPrintSetup & { readOnlyReason: string } {
  checkXlsxPrintSetup(value);
  if (typeof record(value).readOnlyReason !== "string")
    throw new Error("Invalid print protection query");
  return value as XlsxPrintSetup & { readOnlyReason: string };
}
export function checkPrintOptions(value: PrintOptions | null): void {
  if (value === null) return;
  const options = record(value);
  if (
    !finite(options.width, 36, 14400) ||
    !finite(options.height, 36, 14400) ||
    !["left", "top", "right", "bottom"].every((key) =>
      finite(options[key], 0, 14400),
    ) ||
    (options.range !== undefined && typeof options.range !== "string")
  )
    throw new Error("Invalid print paper override");
}
