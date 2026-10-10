import type { Budget } from "@open-document/wasm/foundation";

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
  | { operation: "budget" | "query" | "saveDocx" | "flow" }
  | { operation: "layout"; profile: Record<string, string> }
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
