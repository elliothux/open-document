import { pptxMediaVolumeMax } from "@open-document/wasm/engine-source";
import { integer, record } from "@open-document/wasm/abi/validation";

export interface PptxFragmentMedia<Bytes = string> {
  kind: "audio" | "video";
  contentType: string;
  /** Local media with the same byte limits as insertion. */
  bytes: Bytes;
}

export interface PptxMediaPlayback {
  loop: boolean;
  /** Native OOXML volume units, from 0 to 100000. */
  volume: number;
  mute: boolean;
}
export function checkMediaPlayback(value: unknown): void {
  const settings = record(value);
  if (
    typeof settings.loop !== "boolean" ||
    !integer(settings.volume, 0, pptxMediaVolumeMax) ||
    typeof settings.mute !== "boolean" ||
    Object.keys(settings).length !== 3 ||
    Object.keys(settings).some(
      (key) => !["loop", "volume", "mute"].includes(key),
    )
  )
    throw new Error("Invalid media playback settings");
}
export interface PptxMedia {
  kind: "audio" | "video";
  key: string;
  contentType: string;
  poster: string | null;
  reason: string;
}

function mediaTypes(kind: "audio" | "video"): readonly string[] {
  return kind === "audio"
    ? ["audio/wav", "audio/mpeg", "audio/mp4", "audio/webm"]
    : ["video/mp4", "video/webm"];
}

export function checkPptxMediaInput(value: unknown): void {
  const change = record(value);
  const placement = change.action === "insertMedia";
  const keys = [
    "action",
    "kind",
    "contentType",
    "bytes",
    "poster",
    ...(placement ? ["x", "y", "width", "height"] : []),
  ];
  if (
    (!placement && change.action !== "fillMedia") ||
    (change.kind !== "audio" && change.kind !== "video") ||
    typeof change.contentType !== "string" ||
    !mediaTypes(change.kind).includes(change.contentType) ||
    !(change.bytes instanceof Uint8Array) ||
    !change.bytes.length ||
    !(change.poster instanceof Uint8Array) ||
    !change.poster.length ||
    Object.keys(change).length !== keys.length ||
    Object.keys(change).some((key) => !keys.includes(key))
  )
    throw new Error("Invalid PPTX media input");
  for (const key of placement ? ["x", "y", "width", "height"] : [])
    if (
      typeof change[key] !== "number" ||
      !Number.isFinite(change[key]) ||
      change[key] > 14400 ||
      change[key] < (key === "x" || key === "y" ? -14400 : 0.1)
    )
      throw new Error("Invalid PPTX media placement");
}
