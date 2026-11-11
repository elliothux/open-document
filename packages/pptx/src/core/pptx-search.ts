import { record } from "@open-document/wasm/abi/validation";
import {
  pptxSearchMatchLimit,
  pptxTextFrameUnits,
} from "@open-document/wasm/engine-source";

export interface PptxFindOptions {
  matchCase?: boolean;
  wholeWord?: boolean;
  /** Search all slides, including hidden slides. Defaults to true. */
  all?: boolean;
}
export interface PptxSearchResult {
  revision: number;
  truncated: boolean;
  matches: {
    slide: string;
    object: string;
    anchor: number;
    focus: number;
    hidden: boolean;
    snippet: string;
    reason: string;
  }[];
}
export type PptxSearchCommand =
  | {
      operation: "findPptx";
      revision: number;
      slide: string;
      text: string;
      options: PptxFindOptions;
    }
  | {
      operation: "replacePptxMatches";
      revision: number;
      slide: string;
      text: string;
      options: PptxFindOptions;
      replacement: string;
      index?: number;
      profile: Record<string, string>;
    };

export function pptxFindOptions(
  options: PptxFindOptions,
): Required<PptxFindOptions> {
  const fields = record(options);
  if (
    Object.entries(fields).some(
      ([key, value]) =>
        !["matchCase", "wholeWord", "all"].includes(key) ||
        (value !== undefined && typeof value !== "boolean"),
    )
  )
    throw new Error("Invalid presentation search options");
  return {
    matchCase: options.matchCase ?? false,
    wholeWord: options.wholeWord ?? false,
    all: options.all ?? true,
  };
}

function integer(value: unknown, maximum = 2147483647): boolean {
  return (
    typeof value === "number" &&
    Number.isInteger(value) &&
    value >= 0 &&
    value <= maximum
  );
}
function text(value: unknown): boolean {
  return (
    typeof value === "string" &&
    value.length <= pptxTextFrameUnits &&
    value.isWellFormed() &&
    !Array.from(value).some((c) => {
      const code = c.charCodeAt(0);
      return (
        (code < 32 && ![9, 10, 13].includes(code)) ||
        code === 65534 ||
        code === 65535
      );
    })
  );
}
export function preparePptxSearch(
  command: PptxSearchCommand,
): PptxSearchCommand {
  if (
    !integer(command.revision) ||
    !text(command.text) ||
    !command.text.length ||
    typeof command.slide !== "string" ||
    !command.slide.length ||
    command.slide.length > 4096
  )
    throw new Error("Invalid presentation search input");
  if (
    command.operation === "replacePptxMatches" &&
    (!text(command.replacement) ||
      command.replacement.includes("\r") ||
      (command.index !== undefined &&
        !integer(command.index, pptxSearchMatchLimit - 1)))
  )
    throw new Error("Invalid presentation replacement input");
  return { ...command, options: pptxFindOptions(command.options) };
}
