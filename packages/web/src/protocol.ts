import type {
  Budget,
  DocxSelection,
  DocxPosition,
  NavigationDirection,
} from "@open-document/wasm/foundation";

export type Operation =
  | { operation: "open"; text: string; wasm: ArrayBuffer }
  | { operation: "read" | "undo" }
  | {
      operation: "replace";
      start: number;
      end: number;
      text: string;
    }
  | { operation: "openFoundation"; wasm: ArrayBuffer }
  | { operation: "font"; bytes: Uint8Array; identity: string }
  | { operation: "shape"; text: string; size: number; language: string }
  | { operation: "openDocx"; bytes: Uint8Array; budget: Budget }
  | { operation: "budget" | "query" | "saveDocx" | "flow" | "editState" }
  | {
      operation: "selectDocx" | "selectedText";
      revision: number;
      selection: DocxSelection;
    }
  | {
      operation: "replaceRange";
      revision: number;
      selection: DocxSelection;
      text: string;
      inputGroup?: number | undefined;
    }
  | { operation: "undoDocx" | "redoDocx"; revision: number }
  | { operation: "beginComposition"; revision: number }
  | {
      operation: "updateComposition" | "commitComposition";
      revision: number;
      compositionId: number;
      text: string;
    }
  | { operation: "cancelComposition"; revision: number; compositionId: number }
  | {
      operation: "deleteDocx";
      revision: number;
      direction: "backward" | "forward";
    }
  | { operation: "layout"; profile: Record<string, string> }
  | {
      operation: "hitTest";
      layoutId: number;
      page: number;
      x: number;
      y: number;
    }
  | { operation: "caret"; layoutId: number; position: DocxPosition }
  | {
      operation: "navigateDocx";
      revision: number;
      layoutId: number;
      direction: NavigationDirection;
      extend: boolean;
    }
  | {
      operation: "selectionGeometry";
      layoutId: number;
      selection: DocxSelection;
    }
  | {
      operation: "exportPdf";
      outputBytes: number;
      layoutId?: number | undefined;
    }
  | { operation: "imageBytes"; key: string }
  | {
      operation: "image";
      key: string;
      width: number;
      height: number;
      bytes: Uint8Array;
    }
  | { operation: "replaceNode"; node: number; revision: number; text: string };

export type Request = Operation & { id: number };

export type Response =
  | { id: number; ok: true; value: unknown }
  | {
      id: number;
      ok: false;
      error: string;
      code?: string;
      part?: string;
      offset?: number;
    };
