import type { PdfCommand } from "../core/index.js";
export type Operation =
  | { operation: "initialize"; module: WebAssembly.Module }
  | { operation: "font"; bytes: Uint8Array; identity: string }
  | PdfCommand;
export type Request = Operation & { id: number };
