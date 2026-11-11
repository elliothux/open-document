import { record } from "@open-document/wasm/abi/validation";

export interface PptxConnectorEnd {
  x: number;
  y: number;
  /** Empty for a free endpoint; otherwise an object ID in the same source part. */
  target: string;
  /** Native connection-site index; zero for a free endpoint. */
  site: number;
}
export interface PptxConnector {
  kind:
    | "straight"
    | "rightAngle"
    | "elbow"
    | "elbow4"
    | "elbow5"
    | "curved"
    | "curved2"
    | "curved4"
    | "curved5"
    | null;
  start: PptxConnectorEnd | null;
  end: PptxConnectorEnd | null;
  reason: string;
}
function endpoint(value: unknown): void {
  const point = record(value);
  if (
    Object.keys(point).length !== 4 ||
    [point.x, point.y].some(
      (v) =>
        typeof v !== "number" || !Number.isFinite(v) || Math.abs(v) > 14400,
    ) ||
    typeof point.target !== "string" ||
    point.target.length > 1024 ||
    typeof point.site !== "number" ||
    !Number.isInteger(point.site) ||
    point.site < 0 ||
    point.site > 255 ||
    (!point.target && point.site !== 0)
  )
    throw new Error("Invalid connector endpoint");
}
export function checkPptxConnectorEdit(value: Record<string, unknown>): void {
  if (
    Object.keys(value).some(
      (k) => !["action", "kind", "start", "end"].includes(k),
    )
  )
    throw new Error("Unknown connector edit field");
  if (
    value.kind !== "straight" &&
    value.kind !== "rightAngle" &&
    value.kind !== "elbow" &&
    value.kind !== "elbow4" &&
    value.kind !== "elbow5" &&
    value.kind !== "curved" &&
    value.kind !== "curved2" &&
    value.kind !== "curved4" &&
    value.kind !== "curved5"
  )
    throw new Error("Invalid connector kind");
  endpoint(value.start);
  endpoint(value.end);
}
