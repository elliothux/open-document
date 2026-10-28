import { engineModule, instantiateEngine } from "@open-document/wasm/loader";
import type { EngineHandle } from "@open-document/wasm";
import { FoundationSession } from "./foundation.js";

export function instantiateDocx(module: WebAssembly.Module): FoundationSession {
  const { exports, context } = instantiateEngine(module, "docx");
  return new FoundationSession(exports, context);
}

export function openDocx(engine: EngineHandle): FoundationSession {
  return instantiateDocx(engineModule(engine));
}
