import { engineModule, instantiateEngine } from "@open-document/wasm/loader";
import type { EngineHandle } from "@open-document/wasm";
import { PdfSession } from "./pdf.js";

export function instantiatePdf(module: WebAssembly.Module): PdfSession {
  const { exports, context } = instantiateEngine(module, "pdf");
  return new PdfSession(exports, context);
}

export function openPdf(engine: EngineHandle): PdfSession {
  return instantiatePdf(engineModule(engine));
}
