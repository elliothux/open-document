import { integer, record } from "@open-document/wasm/abi/validation";
import type {
  DrawingBatch,
  DrawCommand,
} from "@open-document/wasm/abi/drawing";
import { checkMediaPlayback, type PptxMediaPlayback } from "./pptx-media.js";

export interface PptxShowMediaState {
  object: string;
  label: string;
  kind: "audio" | "video";
  key: string;
  contentType: string;
  token: number;
  state: "stopped" | "playing" | "paused" | "ended" | "blocked" | "error";
  reason: string;
  visible: boolean;
  playback: PptxMediaPlayback;
}
export interface PptxShowMediaChange {
  object: string;
  token: number;
  action: "play" | "pause" | "stop" | "ended" | "paused" | "blocked" | "error";
  message?: string;
}
export interface PptxShowMediaDrawing {
  object: string;
  paths: number[][];
}

export function checkShowMediaChange(value: unknown): void {
  const change = record(value);
  if (
    typeof change.object !== "string" ||
    !change.object ||
    change.object.length > 1024 ||
    !change.object.isWellFormed() ||
    !integer(change.token, 0, 0x7fffffff) ||
    typeof change.action !== "string" ||
    !["play", "pause", "stop", "ended", "paused", "blocked", "error"].includes(
      change.action,
    ) ||
    (["ended", "paused", "blocked", "error"].includes(String(change.action)) &&
      change.token === 0) ||
    Object.keys(change).some(
      (key) => !["object", "token", "action", "message"].includes(key),
    ) ||
    (change.action === "error"
      ? typeof change.message !== "string" ||
        !change.message ||
        change.message.length > 1024 ||
        !change.message.isWellFormed()
      : change.message !== undefined)
  )
    throw new Error("Invalid media playback change");
}

export function checkShowMediaState(value: unknown, active: unknown): void {
  if (!Array.isArray(value) || value.length > 4096 || (!active && value.length))
    throw new Error("Invalid slideshow media");
  const ids = new Set<string>();
  let units = 0,
    players = 0;
  for (const item of value) {
    const media = record(item);
    checkMediaPlayback(media.playback);
    if (
      typeof media.object !== "string" ||
      !media.object ||
      media.object.length > 1024 ||
      ids.has(media.object) ||
      typeof media.label !== "string" ||
      typeof media.key !== "string" ||
      media.key.length > 256 ||
      typeof media.contentType !== "string" ||
      media.contentType.length > 256 ||
      typeof media.reason !== "string" ||
      media.reason.length > 8192 ||
      typeof media.visible !== "boolean" ||
      (media.kind !== "audio" && media.kind !== "video") ||
      !integer(media.token, 0, 0x7fffffff) ||
      typeof media.state !== "string" ||
      !["stopped", "playing", "paused", "ended", "blocked", "error"].includes(
        media.state,
      ) ||
      (media.state !== "stopped" && media.token === 0)
    )
      throw new Error("Invalid slideshow media state");
    for (const text of [
      media.object,
      media.label,
      media.key,
      media.contentType,
      media.reason,
    ]) {
      if (!text.isWellFormed())
        throw new Error("Invalid media description text");
      units += text.length;
    }
    if (["playing", "paused", "ended", "blocked"].includes(String(media.state)))
      players++;
    ids.add(media.object);
  }
  if (units > 1048576 || players > 16)
    throw new Error("Slideshow media exceeds budget");
}

/** Resolve only a core-authored image command path, including nested opacity layers. */
export function mediaImageCommand(
  batch: DrawingBatch,
  path: readonly number[],
): DrawCommand {
  if (path.length < 2 || path.length > 6 || !integer(path[0], 0, 1))
    throw new Error("Invalid media image path");
  const region = batch.regions[path[0]!];
  if (!region) throw new Error("Unknown media drawing region");
  let commands = region.commands;
  for (let depth = 1; depth < path.length; depth++) {
    const index = path[depth];
    if (!integer(index, 0, commands.length - 1))
      throw new Error("Invalid media command index");
    const command = commands[index!]!;
    if (depth === path.length - 1) {
      if (command.op !== "image")
        throw new Error("Media path must reference an image");
      return command;
    }
    if (command.op !== "layer")
      throw new Error("Media path must traverse opacity layers");
    commands = command.commands;
  }
  throw new Error("Missing media command");
}

export function checkShowMediaDrawing(
  batch: DrawingBatch,
  value: unknown,
): void {
  if (!Array.isArray(value) || value.length > 4096)
    throw new Error("Invalid media drawing bindings");
  const ids = new Set<string>(),
    paths = new Set<string>();
  for (const item of value) {
    const binding = record(item);
    if (
      typeof binding.object !== "string" ||
      !binding.object ||
      binding.object.length > 1024 ||
      ids.has(binding.object) ||
      !Array.isArray(binding.paths)
    )
      throw new Error("Invalid media image binding");
    ids.add(binding.object);
    for (const path of binding.paths) {
      if (!Array.isArray(path)) throw new Error("Invalid media image path");
      mediaImageCommand(batch, path);
      const key = path.join(":");
      if (paths.has(key)) throw new Error("Duplicate media image path");
      paths.add(key);
      if (paths.size > 65536)
        throw new Error("Media image bindings exceed budget");
    }
  }
}
