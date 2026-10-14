import { loadEngine, type TextSession } from "@open-document/wasm/engine";
import type { FoundationSession } from "@open-document/wasm/foundation";
import type { Request, Response } from "./protocol";

let text: TextSession | undefined;
let foundation: FoundationSession | undefined;
let busy = false;

async function dispatch(request: Request): Promise<unknown> {
  if (request.operation === "open" || request.operation === "openFoundation") {
    if (text || foundation) throw new Error("Session is already open");
    const engine = await loadEngine(request.wasm);
    if (request.operation === "open") {
      text = engine.openText(request.text);
      return text.read();
    }
    foundation = engine.openFoundation();
    return null;
  }
  switch (request.operation) {
    case "read":
    case "undo":
    case "replace":
      if (!text) throw new Error("Text session is not open");
      if (request.operation === "undo") text.undo();
      if (request.operation === "replace")
        text.replace(request.start, request.end, request.text);
      return text.read();
    default:
      if (!foundation) throw new Error("Foundation session is not open");
      switch (request.operation) {
        case "budget":
          return foundation.defaultBudget();
        case "font":
          foundation.addFont(request.bytes, request.identity);
          return null;
        case "shape":
          return foundation.shape(request.text, request.size, request.language);
        case "openDocx":
          return foundation.openDocx(request.bytes, request.budget);
        case "query":
          return foundation.query();
        case "editState":
          return foundation.editState();
        case "beginComposition":
          return foundation.beginComposition(request.revision);
        case "updateComposition":
          return foundation.updateComposition(
            request.revision,
            request.compositionId,
            request.text,
          );
        case "commitComposition":
          return foundation.commitComposition(
            request.revision,
            request.compositionId,
            request.text,
          );
        case "cancelComposition":
          return foundation.cancelComposition(
            request.revision,
            request.compositionId,
          );
        case "selectDocx":
          return foundation.selectDocx(request.revision, request.selection);
        case "selectedText":
          return foundation.selectedText(request.revision, request.selection);
        case "replaceRange":
          return foundation.replaceRange(
            request.revision,
            request.selection,
            request.text,
            request.inputGroup,
          );
        case "undoDocx":
          return foundation.undoDocx(request.revision);
        case "deleteDocx":
          return foundation.deleteDocx(request.revision, request.direction);
        case "redoDocx":
          return foundation.redoDocx(request.revision);
        case "replaceNode":
          return foundation.replaceNode(
            request.node,
            request.revision,
            request.text,
          );
        case "saveDocx":
          return foundation.saveDocx();
        case "flow":
          return foundation.flow();
        case "layout":
          return foundation.layout(request.profile);
        case "hitTest":
          return foundation.hitTest(
            request.layoutId,
            request.page,
            request.x,
            request.y,
          );
        case "caret":
          return foundation.caret(request.layoutId, request.position);
        case "navigateDocx":
          return foundation.navigateDocx(
            request.revision,
            request.layoutId,
            request.direction,
            request.extend,
          );
        case "selectionGeometry":
          return foundation.selectionGeometry(
            request.layoutId,
            request.selection,
          );
        case "exportPdf":
          return foundation.exportPdf(request.outputBytes, request.layoutId);
        case "imageBytes":
          return foundation.imageBytes(request.key);
        case "image":
          foundation.addImage(
            request.key,
            request.width,
            request.height,
            request.bytes,
          );
          return null;
      }
  }
}

globalThis.onmessage = async (event: MessageEvent<Request>) => {
  const request = event.data;
  let response: Response;
  if (busy) {
    globalThis.postMessage({
      id: request.id,
      ok: false,
      error: "Await the previous operation",
    });
    return;
  }
  busy = true;
  try {
    response = { id: request.id, ok: true, value: await dispatch(request) };
  } catch (error) {
    response = {
      id: request.id,
      ok: false,
      error: error instanceof Error ? error.message : String(error),
      ...(error instanceof Error &&
      error.name === "DocumentError" &&
      "code" in error &&
      typeof error.code === "string" &&
      "part" in error &&
      typeof error.part === "string" &&
      "offset" in error &&
      typeof error.offset === "number"
        ? { code: error.code, part: error.part, offset: error.offset }
        : {}),
    };
  } finally {
    busy = false;
  }
  globalThis.postMessage(response);
};
