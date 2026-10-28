import { serveWorker } from "@open-document/web-core/worker";
import { instantiatePptx } from "../core/engine.js";
import type { PptxSession } from "../core/index.js";
import type { Operation } from "./protocol.js";
let presentation: PptxSession | undefined;
async function dispatch(request: Operation): Promise<unknown> {
  if (request.operation === "initialize") {
    if (presentation) throw new Error("Session is already open");
    presentation = await instantiatePptx(request.module);
    return null;
  }
  if (!presentation) throw new Error("Session is not open");
  if (request.operation === "font") {
    presentation.addFont(request.bytes, request.identity);
    return null;
  }
  if (request.operation === "budget") return presentation.defaultBudget();
  return presentation.execute(request);
}
serveWorker(dispatch);
