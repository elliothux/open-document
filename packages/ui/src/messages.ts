import type { Locale } from "./types.js";
import { en, type Messages } from "./messages-en.js";
import { zh } from "./messages-zh.js";

export function messages(locale: Locale): Messages {
  return locale === "zh-CN" ? zh : en;
}
export type MessageKey = keyof Messages;
