import { engineModule, instantiateEngine } from "@open-document/wasm/loader";
import type { EngineHandle } from "@open-document/wasm";
import { XlsxSession } from "./xlsx.js";

export function instantiateXlsx(module: WebAssembly.Module): XlsxSession {
  const { exports, context } = instantiateEngine(module, "xlsx");
  return new XlsxSession(exports, context);
}

export function openXlsx(engine: EngineHandle): XlsxSession {
  return instantiateXlsx(engineModule(engine));
}
