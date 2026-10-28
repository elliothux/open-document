import { serveWorker } from "@open-document/web-core/worker";
import { instantiatePdf } from "../core/engine.js";
import type { PdfSession } from "../core/index.js";
import type { Operation } from "./protocol.js";
let pdf: PdfSession | undefined;
async function dispatch(request: Operation): Promise<unknown> {
  if (request.operation === "initialize") {
    if (pdf) throw new Error("Session is already open");
    pdf = await instantiatePdf(request.module);
    return null;
  }
  if (!pdf) throw new Error("Session is not open");
  if (request.operation === "font") {
    pdf.addFont(request.bytes, request.identity);
    return null;
  }
  return pdf.execute(request);
}
serveWorker(dispatch);
