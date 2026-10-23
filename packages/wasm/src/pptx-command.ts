import type { PptxShowCommand } from "./pptx-show.js";
import type { PptxSearchCommand } from "./pptx-search.js";
import type { PptxOutputCommand } from "./pptx-output.js";
import type { Budget } from "./foundation.js";
import type { PptxSlideEdit } from "./pptx-slides.js";
import type {
  PptxObjectEdit,
  PptxSelection,
  PptxPoint,
} from "./pptx-objects.js";
import type { DrawRect } from "./drawing.js";

export type PptxCommand =
  | PptxShowCommand
  | PptxSearchCommand
  | PptxOutputCommand
  | { operation: "createPptx"; budget: Budget; dateTime?: string }
  | {
      operation: "openPptx";
      bytes: Uint8Array;
      budget: Budget;
      dateTime?: string;
    }
  | {
      operation: "dateTimePptx";
      revision: number;
      dateTime?: string;
      profile: Record<string, string>;
    }
  | { operation: "queryPptx" }
  | { operation: "followPptxHyperlink"; revision: number }
  | {
      operation: "editPptxSlides";
      revision: number;
      slide: string;
      change: PptxSlideEdit;
      profile: Record<string, string>;
    }
  | {
      operation: "editPptxObjects";
      revision: number;
      change: PptxObjectEdit;
      profile: Record<string, string>;
    }
  | ({ operation: "selectPptx"; revision: number } & PptxSelection)
  | {
      operation: "objectFragmentImagesPptx" | "objectFragmentMediaPptx";
      revision: number;
      fragment: string;
    }
  | {
      operation: "pastePptxFragment" | "pastePptxObjects";
      revision: number;
      fragment: string;
      profile: Record<string, string>;
    }
  | {
      operation: "replacePptx";
      revision: number;
      text: string;
      profile: Record<string, string>;
      candidateId?: number;
    }
  | {
      operation: "deletePptx";
      revision: number;
      backward: boolean;
      profile: Record<string, string>;
    }
  | {
      operation: "undoPptx" | "redoPptx" | "savePptx" | "copyPptx";
      revision: number;
    }
  | { operation: "layoutPptx"; profile: Record<string, string> }
  | {
      operation: "hitPptx";
      layoutId: number;
      x: number;
      y: number;
      tolerance: number;
      /** Return editable group text members at this point. */
      text?: boolean;
    }
  | { operation: "selectionPptx"; layoutId: number; gridScale?: number }
  | {
      operation: "navigatePptx";
      revision: number;
      layoutId: number;
      direction:
        "next" | "previous" | "left" | "right" | "up" | "down" | "home" | "end";
      extend: boolean;
    }
  | {
      operation: "beginPptx";
      revision: number;
      kind: "text" | "transform" | "connector" | "adjustment";
    }
  | ({
      operation: "beginGuidePptx";
      revision: number;
      tolerance: number;
    } & PptxPoint)
  | ({
      operation: "transformPptx";
      revision: number;
      candidateId: number;
    } & DrawRect)
  | {
      operation: "dragPptx";
      revision: number;
      candidateId: number;
      dx: number;
      dy: number;
      handle: number;
      tolerance?: number;
      shift?: boolean;
      center?: boolean;
    }
  | {
      operation: "finishPptx";
      revision: number;
      candidateId: number;
      profile: Record<string, string>;
    }
  | { operation: "cancelPptx"; revision: number; candidateId: number }
  | {
      operation: "imagePptx";
      key: string;
      width: number;
      height: number;
      bytes: Uint8Array;
    };

const names: ReadonlySet<string> = new Set([
  "openPptx",
  "createPptx",
  "queryPptx",
  "dateTimePptx",
  "followPptxHyperlink",
  "findPptx",
  "replacePptxMatches",
  "editPptxObjects",
  "editPptxSlides",
  "selectPptx",
  "replacePptx",
  "deletePptx",
  "undoPptx",
  "redoPptx",
  "savePptx",
  "copyPptx",
  "pastePptxFragment",
  "pastePptxObjects",
  "objectFragmentImagesPptx",
  "objectFragmentMediaPptx",
  "layoutPptx",
  "printLayoutPptx",
  "hitPptx",
  "selectionPptx",
  "navigatePptx",
  "beginPptx",
  "beginGuidePptx",
  "transformPptx",
  "dragPptx",
  "finishPptx",
  "cancelPptx",
  "imageBytesPptx",
  "mediaBytesPptx",
  "imagePptx",
  "imageKeysPptx",
  "exportPptxPdf",
  "controlShowPptx",
  "inkShowPptx",
  "mediaShowPptx",
  "layoutShowPptx",
  "imageKeysShowPptx",
]);
export function isPptxCommand(value: {
  operation: string;
}): value is PptxCommand {
  return names.has(value.operation);
}

export function checkPptxTextFragment(value: unknown): asserts value is string {
  if (
    typeof value !== "string" ||
    !value.isWellFormed() ||
    value.length > 1048576
  )
    throw new Error("Invalid PPTX text fragment");
}

export function checkPptxObjectFragment(
  value: unknown,
): asserts value is string {
  if (
    typeof value !== "string" ||
    !value.isWellFormed() ||
    value.length > 100663296
  )
    throw new Error("Invalid PPTX object fragment");
}
