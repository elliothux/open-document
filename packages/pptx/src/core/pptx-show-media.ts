import { integer, record } from "@open-document/wasm/abi/validation";
import type {
  DrawingBatch,
  DrawCommand,
} from "@open-document/wasm/abi/drawing";
import type { PptxMediaPlayback } from "./pptx-media.js";

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
