import type { PptxCommand } from "../core/index.js";
export type Operation =
  | { operation: "initialize"; module: WebAssembly.Module }
  | { operation: "font"; bytes: Uint8Array; identity: string }
  | { operation: "budget" }
  | PptxCommand;
export type Request = Operation & { id: number };
