import { record } from "./validation.js";
import { checkGradientStops, type GradientStop } from "./drawing.js";
import { imageInsets } from "./pptx-objects.js";
import {
  checkPptxFooterContent,
  type PptxFooterContent,
} from "./pptx-footer.js";
import {
  checkPptxThemeColor,
  checkPptxThemeFont,
  type PptxThemeSlot,
} from "./pptx-theme.js";

export type PptxBackgroundFill =
  | { kind: "solid"; color: string }
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

function checkBackgroundImageFormat(fill: Record<string, unknown>): void {
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
  if (fill.kind === "linear") checkGradientStops(fill.stops);
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
        typeof fill.scaled === "boolean")
    ) ||
    Object.keys(fill).some(
      (key) =>
        !(
          fill.kind === "solid"
            ? ["kind", "color"]
            : ["kind", "stops", "angle", "scaled"]
        ).includes(key),
    )
  )
    throw new Error("Invalid slide background fill");
}

export interface PptxTransition {
  kind: "none" | "fade" | "push";
  duration: number;
  direction: "left" | "right" | "up" | "down";
}
export interface PptxPlaybackState {
  transition: {
    value: PptxTransition | null;
    advance: PptxAdvance;
    reason: string;
  };
  animations: { items: PptxAnimation[]; reason: string };
}
export interface PptxAnimation {
  object: string;
  kind: "appear" | "disappear" | "fadeIn" | "fadeOut";
  trigger: "click" | "with" | "after";
  delay: number;
  duration: number;
  repeat: number;
}
function pptxAnimations(value: unknown): void {
  if (!Array.isArray(value) || value.length > 128)
    throw new Error("Invalid object animation list");
  for (const item of value) {
    const animation = record(item);
    if (
      typeof animation.object !== "string" ||
      !animation.object ||
      animation.object.length > 1024 ||
      !animation.object.isWellFormed() ||
      !["appear", "disappear", "fadeIn", "fadeOut"].includes(
        String(animation.kind),
      ) ||
      !["click", "with", "after"].includes(String(animation.trigger)) ||
      typeof animation.delay !== "number" ||
      !Number.isInteger(animation.delay) ||
      animation.delay < 0 ||
      animation.delay > 60000 ||
      typeof animation.duration !== "number" ||
      !Number.isInteger(animation.duration) ||
      typeof animation.repeat !== "number" ||
      !Number.isInteger(animation.repeat) ||
      animation.repeat < 1 ||
      animation.repeat > 100 ||
      (["appear", "disappear"].includes(String(animation.kind))
        ? animation.duration !== 1 || animation.repeat !== 1
        : animation.duration < 100 || animation.duration > 60000) ||
      Object.keys(animation).length !== 6 ||
      Object.keys(animation).some(
        (key) =>
          ![
            "object",
            "kind",
            "trigger",
            "delay",
            "duration",
            "repeat",
          ].includes(key),
      )
    )
      throw new Error("Invalid object animation");
  }
}
export interface PptxAdvance {
  click: boolean;
  after: number | null;
}
function pptxAdvance(value: unknown): void {
  const advance = record(value);
  if (
    typeof advance.click !== "boolean" ||
    (advance.after !== null &&
      (typeof advance.after !== "number" ||
        !Number.isInteger(advance.after) ||
        advance.after < 0 ||
        advance.after > 3600000)) ||
    Object.keys(advance).length !== 2 ||
    Object.keys(advance).some((key) => !["click", "after"].includes(key))
  )
    throw new Error("Invalid slide advance");
}
export function pptxTransition(value: unknown): void {
  const effect = record(value);
  if (
    !["none", "fade", "push"].includes(String(effect.kind)) ||
    !["left", "right", "up", "down"].includes(String(effect.direction)) ||
    typeof effect.duration !== "number" ||
    !Number.isInteger(effect.duration) ||
    (effect.kind === "none"
      ? effect.duration !== 0
      : effect.duration < 100 || effect.duration > 60000) ||
    (effect.kind !== "push" && effect.direction !== "left") ||
    Object.keys(effect).length !== 3 ||
    Object.keys(effect).some(
      (key) => !["kind", "duration", "direction"].includes(key),
    )
  )
    throw new Error("Invalid slide transition");
}
export function pptxPlaybackState(value: unknown): void {
  const state = record(record(value).transition);
  if (typeof state.reason !== "string" || state.reason.length > 8192)
    throw new Error("Invalid transition state");
  if (state.value !== null) pptxTransition(state.value);
  pptxAdvance(state.advance);
  const animations = record(record(value).animations);
  if (typeof animations.reason !== "string" || animations.reason.length > 8192)
    throw new Error("Invalid animation state");
  pptxAnimations(animations.items);
}

export type PptxSlideEdit =
  | { action: "animations"; value: PptxAnimation[] }
  | { action: "advance"; value: PptxAdvance }
  | { action: "transition"; value: PptxTransition | null }
  | {
      action: "commentAdd";
      text: string;
      author: PptxCommentAuthor;
      date: string;
      parent: string | null;
    }
  | { action: "commentUpdate"; id: string; text: string }
  | { action: "commentRemove"; id: string }
  | { action: "themeColor"; slot: PptxThemeSlot; color: string }
  | {
      action: "themeFont";
      kind: "major" | "minor";
      script: string;
      font: string;
    }
  | { action: "layout"; id: string }
  | { action: "resetLayout" }
  | { action: "notes"; text: string }
  | { action: "firstSlideNumber"; number: number }
  | { action: "footer"; value: PptxFooterContent; allSlides: boolean }
  | { action: "sectionAdd"; name: string }
  | { action: "sectionRename"; id: string; name: string }
  | { action: "sectionRemove"; id: string }
  | { action: "sectionRemoveAll" }
  | { action: "sectionDelete"; id: string }
  | { action: "sectionMove"; id: string; index: number }
  | { action: "add" }
  | { action: "copy" }
  | { action: "delete" }
  | { action: "move"; index: number }
  | { action: "hidden"; hidden: boolean }
  | { action: "background"; value: PptxBackgroundFill | null }
  | { action: "backgroundImage"; bytes: Uint8Array; mode: "stretch" | "tile" }
  | {
      action: "backgroundImageInsets";
      insets: [number, number, number, number];
    }
  | {
      action: "backgroundImageFormat";
      mode: "stretch" | "tile";
      crop: [number, number, number, number];
      opacity: number;
    }
  | { action: "size"; width: number; height: number };

export function checkPptxSlideEdit(value: unknown): void {
  const change = record(value);
  if (change.action === "animations") {
    if (Object.keys(change).some((key) => !["action", "value"].includes(key)))
      throw new Error("Invalid object animation edit");
    pptxAnimations(change.value);
    return;
  }
  if (change.action === "transition" || change.action === "advance") {
    if (Object.keys(change).some((key) => !["action", "value"].includes(key)))
      throw new Error("Invalid transition edit");
    if (change.action === "advance") pptxAdvance(change.value);
    else if (change.value !== null) pptxTransition(change.value);
    return;
  }
  if (change.action === "backgroundImageInsets") {
    imageInsets(change.insets);
    if (
      Object.keys(change).length !== 2 ||
      Object.keys(change).some((key) => !["action", "insets"].includes(key))
    )
      throw new Error("Invalid background image destination edit");
    return;
  }
  if (change.action === "firstSlideNumber") {
    if (
      typeof change.number !== "number" ||
      !Number.isInteger(change.number) ||
      change.number < 0 ||
      change.number > 0xffffffff ||
      Object.keys(change).some((key) => !["action", "number"].includes(key))
    )
      throw new Error("Invalid first slide number");
    return;
  }
  if (change.action === "footer") {
    if (
      typeof change.allSlides !== "boolean" ||
      Object.keys(change).some(
        (key) => !["action", "value", "allSlides"].includes(key),
      )
    )
      throw new Error("Invalid slide footer edit");
    checkPptxFooterContent(change.value);
    return;
  }
  if (change.action === "backgroundImageFormat") {
    checkBackgroundImageFormat(change);
    if (
      Object.keys(change).some(
        (key) => !["action", "mode", "crop", "opacity"].includes(key),
      )
    )
      throw new Error("Invalid background picture format");
    return;
  }
  if (change.action === "backgroundImage") {
    if (
      (change.mode !== "stretch" && change.mode !== "tile") ||
      !(change.bytes instanceof Uint8Array) ||
      !change.bytes.length ||
      change.bytes.length > 4194304 ||
      Object.keys(change).some(
        (key) => !["action", "mode", "bytes"].includes(key),
      )
    )
      throw new Error("Invalid background picture edit");
    return;
  }
  if (
    typeof change.action === "string" &&
    ["commentAdd", "commentUpdate", "commentRemove"].includes(change.action)
  ) {
    checkCommentEdit(change);
    return;
  }
  if (change.action === "themeFont") {
    checkPptxThemeFont(change);
    return;
  }
  if (change.action === "themeColor") {
    checkPptxThemeColor(change);
    return;
  }
  if (change.action === "resetLayout") {
    if (Object.keys(change).length !== 1)
      throw new Error("Reset layout accepts only an action");
    return;
  }
  if (change.action === "layout") {
    if (
      typeof change.id !== "string" ||
      !change.id ||
      change.id.length > 65535 ||
      !change.id.isWellFormed() ||
      Object.keys(change).some((key) => !["action", "id"].includes(key))
    )
      throw new Error("Invalid slide layout identity");
    return;
  }
  if (change.action === "notes") {
    if (
      typeof change.text !== "string" ||
      change.text.length > 32767 ||
      !change.text.isWellFormed() ||
      Array.from(change.text).some((c) => {
        const code = c.codePointAt(0)!;
        return (
          (code < 32 && ![9, 10, 13].includes(code)) ||
          code === 65534 ||
          code === 65535
        );
      })
    )
      throw new Error("Invalid slide notes");
    return;
  }
  if (
    typeof change.action === "string" &&
    [
      "sectionAdd",
      "sectionRename",
      "sectionRemove",
      "sectionDelete",
      "sectionMove",
    ].includes(change.action)
  ) {
    if (change.action === "sectionAdd" || change.action === "sectionRename")
      sectionName(change.name, true);
    if (
      change.action !== "sectionAdd" &&
      (typeof change.id !== "string" || !sectionGuid.test(change.id))
    )
      throw new Error("Invalid section identity");
    if (
      change.action === "sectionMove" &&
      (!Number.isInteger(change.index) ||
        Number(change.index) < 0 ||
        Number(change.index) >= 256)
    )
      throw new Error("Invalid section position");
    return;
  }
  if (change.action === "size") {
    if (
      ![change.width, change.height].every(
        (value) =>
          typeof value === "number" &&
          Number.isFinite(value) &&
          value >= 1 &&
          value <= 14400,
      )
    )
      throw new Error("Invalid slide size");
    return;
  }
  if (change.action === "background") {
    if (change.value !== null) checkPptxBackgroundFill(change.value);
    return;
  }
  if (
    typeof change.action === "string" &&
    ["add", "copy", "delete", "sectionRemoveAll"].includes(change.action)
  )
    return;
  if (
    change.action === "move" &&
    typeof change.index === "number" &&
    Number.isInteger(change.index) &&
    change.index >= 0 &&
    change.index < 256
  )
    return;
  if (change.action === "hidden" && typeof change.hidden === "boolean") return;
  throw new Error("Invalid slide edit");
}

export interface PptxCommentAuthor {
  name: string;
  initials: string;
}
export interface PptxComment {
  id: string;
  author: string;
  initials: string;
  date: string;
  text: string;
  parent: string | null;
}
export interface PptxComments {
  items: PptxComment[];
  reason: string;
}
const commentId = /^(0|[1-9]\d{0,9}):(0|[1-9]\d{0,9})$/u;
function validCommentId(value: unknown): value is string {
  return (
    typeof value === "string" &&
    commentId.test(value) &&
    value.split(":").every((n) => Number(n) <= 4294967295)
  );
}
function commentText(
  value: unknown,
  max: number,
  required = false,
): value is string {
  return (
    typeof value === "string" &&
    value.length <= max &&
    value.isWellFormed() &&
    (!required || !!value.trim()) &&
    !Array.from(value).some((c) => {
      const n = c.codePointAt(0)!;
      return (n < 32 && ![9, 10, 13].includes(n)) || n === 65534 || n === 65535;
    })
  );
}
function checkCommentEdit(change: Record<string, unknown>): void {
  const add = change.action === "commentAdd",
    update = change.action === "commentUpdate";
  const fields = add
    ? ["action", "text", "author", "date", "parent"]
    : update
      ? ["action", "id", "text"]
      : ["action", "id"];
  if (
    Object.keys(change).some((key) => !fields.includes(key)) ||
    (!add && !validCommentId(change.id)) ||
    ((add || update) && !commentText(change.text, 32767, true))
  )
    throw new Error("Invalid comment edit");
  if (!add) return;
  const author = record(change.author);
  if (
    !commentText(author.name, 255, true) ||
    !commentText(author.initials, 32) ||
    Array.from(author.name + author.initials).some(
      (c) => c.codePointAt(0)! < 32,
    ) ||
    Object.keys(author).some((key) => !["name", "initials"].includes(key)) ||
    (change.parent !== null && !validCommentId(change.parent)) ||
    typeof change.date !== "string" ||
    !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{3})?Z$/u.test(change.date) ||
    change.date.startsWith("0000") ||
    !Number.isFinite(Date.parse(change.date)) ||
    new Date(change.date).toISOString() !==
      (change.date.length === 20
        ? change.date.slice(0, 19) + ".000Z"
        : change.date)
  )
    throw new Error("Invalid comment author, date or reply parent");
}
export function pptxComments(value: unknown): PptxComments {
  const result = record(value);
  if (
    typeof result.reason !== "string" ||
    !Array.isArray(result.items) ||
    result.items.length > 4096
  )
    throw new Error("Invalid comment query");
  const parents = new Map<string, string | null>();
  let units = 0;
  for (const item of result.items) {
    const entry = record(item);
    if (
      !validCommentId(entry.id) ||
      parents.has(entry.id) ||
      !commentText(entry.author, 255) ||
      !commentText(entry.initials, 32) ||
      !commentText(entry.date, 64) ||
      !commentText(entry.text, 32767) ||
      (entry.parent !== null && !validCommentId(entry.parent))
    )
      throw new Error("Invalid comment entry");
    parents.set(entry.id, entry.parent);
    units += entry.text.length;
  }
  if (units > 1048576) throw new Error("Comment query exceeds text budget");
  for (const parent of parents.values())
    if (parent !== null && parents.get(parent) !== null)
      throw new Error("Invalid comment thread");
  return value as PptxComments;
}

export interface PptxSection {
  id: string;
  name: string;
  slides: string[];
}
export interface PptxSections {
  items: PptxSection[];
  reason: string;
}

export interface PptxSlideLayouts {
  current: string;
  choices: { id: string; name: string; master: string; masterName: string }[];
  reason: string;
}

export function pptxSlideLayouts(value: unknown): PptxSlideLayouts {
  const state = record(value);
  if (
    typeof state.current !== "string" ||
    !state.current.isWellFormed() ||
    state.current.length > 65535 ||
    typeof state.reason !== "string" ||
    !Array.isArray(state.choices) ||
    state.choices.length > 256
  )
    throw new Error("Invalid slide layout catalog");
  const ids = new Set<string>();
  let units = 0;
  for (const value of state.choices) {
    const choice = record(value);
    for (const key of ["id", "name", "master", "masterName"]) {
      const text = choice[key];
      if (
        typeof text !== "string" ||
        !text.isWellFormed() ||
        text.length > (key === "name" || key === "masterName" ? 1024 : 65535)
      )
        throw new Error("Invalid slide layout entry");
      units += text.length;
    }
    if (
      typeof choice.id !== "string" ||
      typeof choice.master !== "string" ||
      !choice.id ||
      !choice.master ||
      ids.has(choice.id) ||
      units > 1048576
    )
      throw new Error("Invalid slide layout identity or budget");
    ids.add(choice.id);
  }
  if ((!state.reason || state.choices.length) && !ids.has(state.current))
    throw new Error("Missing current slide layout");
  return value as PptxSlideLayouts;
}
const sectionGuid =
  /^\{[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\}$/iu;
function sectionName(value: unknown, required: boolean): void {
  if (
    typeof value !== "string" ||
    value.length > 255 ||
    !value.isWellFormed() ||
    (required && !value.trim()) ||
    Array.from(value).some((c) => {
      const n = c.codePointAt(0)!;
      return (n < 32 && ![9, 10, 13].includes(n)) || n === 65534 || n === 65535;
    })
  )
    throw new Error("Invalid section name");
}
export function pptxSections(value: unknown, slides: string[]): PptxSections {
  const result = record(value);
  if (
    typeof result.reason !== "string" ||
    !Array.isArray(result.items) ||
    result.items.length > 256
  )
    throw new Error("Invalid section query");
  const ids = new Set<string>();
  let previous = -1;
  for (const item of result.items) {
    const section = record(item);
    if (
      typeof section.id !== "string" ||
      !sectionGuid.test(section.id) ||
      ids.has(section.id.toUpperCase()) ||
      !Array.isArray(section.slides) ||
      section.slides.length > 256
    )
      throw new Error("Invalid section query identity or slides");
    ids.add(section.id.toUpperCase());
    sectionName(section.name, false);
    for (const id of section.slides) {
      const index = typeof id === "string" ? slides.indexOf(id) : -1;
      if (index < 0 || (previous >= 0 && index !== previous + 1))
        throw new Error("Invalid section slide coverage");
      previous = index;
    }
  }
  if (previous >= 0 && previous !== slides.length - 1)
    throw new Error("Incomplete section slide coverage");
  return value as PptxSections;
}
