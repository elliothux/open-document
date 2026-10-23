import { integer, record } from "./validation.js";

export interface PptxFragmentMedia {
  kind: "audio" | "video";
  contentType: string;
  /** Base64-encoded local media, with the same byte limits as insertion. */
  bytes: string;
}

export function checkPptxFragmentMedia(value: unknown): void {
  if (!Array.isArray(value) || value.length > 64)
    throw new Error("Invalid PPTX clipboard media resources");
  let total = 0;
  for (const item of value) {
    const media = record(item);
    if (
      Object.keys(media).length !== 3 ||
      (media.kind !== "audio" && media.kind !== "video") ||
      typeof media.contentType !== "string" ||
      !mediaTypes(media.kind).includes(media.contentType) ||
      typeof media.bytes !== "string" ||
      !media.bytes.length ||
      media.bytes.length > 22369624 ||
      media.bytes.length % 4 !== 0 ||
      !/^[A-Za-z0-9+/]*={0,2}$/.test(media.bytes)
    )
      throw new Error("Invalid PPTX clipboard media resource");
    const size =
      (media.bytes.length / 4) * 3 -
      (media.bytes.endsWith("==") ? 2 : media.bytes.endsWith("=") ? 1 : 0);
    if (size > 16777216) throw new Error("PPTX clipboard media exceeds 16MiB");
    total += size;
    if (total > 67108864) throw new Error("PPTX clipboard media exceeds 64MiB");
  }
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
    !integer(settings.volume, 0, 100000) ||
    typeof settings.mute !== "boolean" ||
    Object.keys(settings).length !== 3 ||
    Object.keys(settings).some(
      (key) => !["loop", "volume", "mute"].includes(key),
    )
  )
    throw new Error("Invalid media playback settings");
}
export function checkMediaPlaybackQuery(value: unknown): void {
  const query = record(value);
  if (
    typeof query.reason !== "string" ||
    query.reason.length > 8192 ||
    (query.value !== null && query.reason)
  )
    throw new Error("Invalid media playback query");
  if (query.value !== null) checkMediaPlayback(query.value);
}

export interface PptxMedia {
  kind: "audio" | "video";
  key: string;
  contentType: string;
  poster: string | null;
  reason: string;
}

export function checkPptxMedia(value: unknown): void {
  if (value === null) return;
  const media = record(value);
  if (
    (media.kind !== "audio" && media.kind !== "video") ||
    typeof media.key !== "string" ||
    media.key.length > 256 ||
    typeof media.contentType !== "string" ||
    media.contentType.length > 256 ||
    (media.poster !== null &&
      (typeof media.poster !== "string" ||
        !media.poster ||
        media.poster.length > 256)) ||
    typeof media.reason !== "string" ||
    (!media.reason &&
      (!media.key ||
        !media.poster ||
        !mediaTypes(media.kind).includes(media.contentType)))
  )
    throw new Error("Invalid PPTX media descriptor");
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
    change.bytes.length > 16777216 ||
    !(change.poster instanceof Uint8Array) ||
    !change.poster.length ||
    change.poster.length > 4194304 ||
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
