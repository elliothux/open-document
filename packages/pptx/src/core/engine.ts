import { engineModule, instantiateEngine } from "@open-document/wasm/loader";
import type { EngineHandle } from "@open-document/wasm";
import { PptxSession } from "./pptx.js";

export function instantiatePptx(module: WebAssembly.Module): PptxSession {
  const { exports, context } = instantiateEngine(module, "pptx");
  return new PptxSession(exports, context);
}

export function openPptx(engine: EngineHandle): PptxSession {
  return instantiatePptx(engineModule(engine));
}
