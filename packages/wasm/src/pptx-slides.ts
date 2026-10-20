import { record } from "./validation.js";
import type { PptxTextFormat } from "./pptx-format.js";
import {
  checkPptxMasterStyleEdit,
  checkPptxGuides,
  type PptxGuide,
  type PptxMasterParagraphFormat,
} from "./pptx-view.js";
import {
  checkPptxShowSettings,
  pptxShowSettingsState,
  type PptxShowSettings,
} from "./pptx-show-settings.js";
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

export type { PptxBackground, PptxBackgroundFill } from "./pptx-background.js";
import {
  checkPptxBackgroundFill,
  checkBackgroundImageFormat,
  type PptxBackgroundFill,
} from "./pptx-background.js";
export {
  checkPptxBackgroundFill,
  checkPptxBackground,
} from "./pptx-background.js";
export interface PptxTransition {
  kind: "none" | "fade" | "push";
  duration: number;
  direction: "left" | "right" | "up" | "down";
}
export interface PptxPlaybackState {
  showSettings: { value: PptxShowSettings | null; reason: string };
  customShows: {
    items: { id: string; name: string; slides: string[] }[];
    reason: string;
  };
  transition: {
    value: PptxTransition | null;
    advance: PptxAdvance;
    reason: string;
  };
  animations: { items: PptxAnimation[]; reason: string };
}
export interface PptxAnimation {
  object: string;
  kind:
    | "appear"
    | "disappear"
    | "fadeIn"
    | "fadeOut"
    | "scale"
    | "rotate"
    | "move"
    | "flyIn"
    | "flyOut"
    | "mediaPlay"
    | "mediaPause"
    | "mediaStop";
  trigger: "click" | "with" | "after";
  delay: number;
  duration: number;
  repeat: number;
  params: number[];
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
      ![
        "appear",
        "disappear",
        "fadeIn",
        "fadeOut",
        "scale",
        "rotate",
        "move",
        "flyIn",
        "flyOut",
        "mediaPlay",
        "mediaPause",
        "mediaStop",
      ].includes(String(animation.kind)) ||
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
      (["appear", "disappear", "mediaPlay", "mediaPause", "mediaStop"].includes(
        String(animation.kind),
      )
        ? animation.duration !== 1 || animation.repeat !== 1
        : animation.duration < 100 || animation.duration > 60000) ||
      !Array.isArray(animation.params) ||
      animation.params.length > 2 ||
      !animation.params.every(
        (value: unknown) =>
          typeof value === "number" &&
          Number.isFinite(value) &&
          Number.isInteger(value),
      ) ||
      (animation.kind === "scale"
        ? animation.params.length !== 2 ||
          !animation.params.every(
            (value: number) => value >= 1 && value <= 1000,
          )
        : animation.kind === "rotate"
          ? animation.params.length !== 1 ||
            Math.abs(animation.params[0]) > 3600
          : animation.kind === "flyIn" || animation.kind === "flyOut"
            ? animation.params.length !== 1 ||
              ![1, 2, 3, 4, 6, 8, 9, 12].includes(animation.params[0])
            : animation.kind === "move"
              ? animation.params.length !== 2 ||
                !animation.params.every(
                  (value: number) => Math.abs(value) <= 14400,
                )
              : animation.params.length !== 0) ||
      Object.keys(animation).length !== 7 ||
      Object.keys(animation).some(
        (key) =>
          ![
            "object",
            "kind",
            "trigger",
            "delay",
            "duration",
            "repeat",
            "params",
          ].includes(key),
      )
    )
      throw new Error("Invalid object animation");
  }
}

function pptxCustomShows(value: unknown, creating: boolean): void {
  if (!Array.isArray(value) || value.length > 32)
    throw new Error("Invalid custom show list");
  const ids = new Set<string>(),
    names = new Set<string>();
  let count = 0;
  for (const entry of value) {
    const item = record(entry);
    if (
      typeof item.id !== "string" ||
      (!(creating && item.id === "") &&
        (String(Number(item.id)) !== item.id ||
          !Number.isInteger(Number(item.id)) ||
          Number(item.id) < 0 ||
          Number(item.id) > 4294967295 ||
          ids.has(item.id))) ||
      typeof item.name !== "string" ||
      !item.name.trim() ||
      item.name.length > 255 ||
      !item.name.isWellFormed() ||
      item.name.split("").some((char) => {
        const code = char.charCodeAt(0);
        return (
          (code < 32 && ![9, 10, 13].includes(code)) ||
          code === 65534 ||
          code === 65535
        );
      }) ||
      names.has(item.name.toLowerCase()) ||
      !Array.isArray(item.slides) ||
      item.slides.length > 256 ||
      !item.slides.every(
        (slide: unknown) =>
          typeof slide === "string" &&
          !!slide &&
          slide.length <= 1024 &&
          slide.isWellFormed(),
      ) ||
      Object.keys(item).length !== 3 ||
      Object.keys(item).some((key) => !["id", "name", "slides"].includes(key))
    )
      throw new Error("Invalid custom show");
    ids.add(item.id);
    names.add(item.name.toLowerCase());
    count += item.slides.length;
  }
  if (count > 4096) throw new Error("Custom show entries exceed budget");
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
  const shows = record(record(value).customShows);
  if (typeof shows.reason !== "string" || shows.reason.length > 8192)
    throw new Error("Invalid custom show state");
  pptxCustomShows(shows.items, false);
  pptxShowSettingsState(value);
  const slides = record(value).slides;
  if (!Array.isArray(slides))
    throw new Error("Missing custom show slide identities");
  const identities = new Set(slides.map((slide: unknown) => record(slide).id));
  if (
    Array.isArray(shows.items) &&
    shows.items.some((entry: unknown) => {
      const members = record(entry).slides;
      return (
        !Array.isArray(members) ||
        members.some((slide: unknown) => !identities.has(slide))
      );
    })
  )
    throw new Error("Unknown custom show slide");
}

export type PptxSlideEdit =
  | { action: "showSettings"; value: PptxShowSettings }
  | { action: "customShows"; value: PptxPlaybackState["customShows"]["items"] }
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
  | {
      action:
        | "addLayout"
        | "copyLayout"
        | "deleteLayout"
        | "deleteMaster"
        | "addMaster"
        | "copyMaster";
    }
  | { action: "sourceName"; name: string }
  | {
      action: "masterTextStyle";
      kind: "title" | "body" | "other";
      level: number;
      format: PptxTextFormat | null;
    }
  | { action: "guides"; visible: boolean; items: PptxGuide[] }
  | { action: "notes"; text: string }
  | {
      action: "masterParagraphStyle";
      kind: "title" | "body" | "other";
      level: number;
      format: PptxMasterParagraphFormat | null;
    }
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
  if (change.action === "guides") {
    if (Object.keys(change).length !== 3) throw new Error("Invalid guide edit");
    checkPptxGuides({ ...change, reason: "" });
    return;
  }
  if (change.action === "showSettings") {
    if (Object.keys(change).length !== 2)
      throw new Error("Invalid slideshow settings edit");
    checkPptxShowSettings(change.value);
    return;
  }
  if (change.action === "customShows") {
    if (Object.keys(change).some((key) => !["action", "value"].includes(key)))
      throw new Error("Invalid custom show edit");
    pptxCustomShows(change.value, true);
    return;
  }
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
  if (change.action === "sourceName") {
    if (!commentText(change.name, 1024) || Object.keys(change).length !== 2)
      throw new Error("Invalid source name edit");
    return;
  }
  if (
    change.action === "masterTextStyle" ||
    change.action === "masterParagraphStyle"
  ) {
    checkPptxMasterStyleEdit(change);
    return;
  }
  if (
    typeof change.action === "string" &&
    [
      "resetLayout",
      "addLayout",
      "copyLayout",
      "deleteLayout",
      "deleteMaster",
      "addMaster",
      "copyMaster",
    ].includes(change.action)
  ) {
    if (Object.keys(change).length !== 1)
      throw new Error("Layout structure edits accept only an action");
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

export { pptxSlideLayouts, type PptxSlideLayouts } from "./pptx-layouts.js";

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
