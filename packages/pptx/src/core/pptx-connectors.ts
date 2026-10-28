import { record, integer } from "@open-document/wasm/abi/validation";

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
    point.site > 15 ||
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
export function checkPptxConnectorQuery(
  value: unknown,
  siteCount: unknown,
): void {
  if (!integer(siteCount, 0, 16))
    throw new Error("Invalid connection site count");
  if (value === null) return;
  const connector = record(value);
  if (typeof connector.reason !== "string")
    throw new Error("Invalid connector reason");
  if (connector.start === null || connector.end === null) {
    if (
      connector.start !== null ||
      connector.end !== null ||
      connector.kind !== null ||
      !connector.reason
    )
      throw new Error("Missing connector endpoints");
  } else {
    if (
      connector.kind !== "straight" &&
      connector.kind !== "rightAngle" &&
      connector.kind !== "elbow" &&
      connector.kind !== "elbow4" &&
      connector.kind !== "elbow5" &&
      connector.kind !== "curved" &&
      connector.kind !== "curved2" &&
      connector.kind !== "curved4" &&
      connector.kind !== "curved5"
    )
      throw new Error("Invalid connector kind");
    endpoint(connector.start);
    endpoint(connector.end);
  }
}
