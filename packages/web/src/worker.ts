import { loadEngine, type TextSession } from "@open-document/wasm/engine";
import type { Request, Response } from "./protocol";

let session: TextSession | undefined;

// One client owns one worker. Requests are sequential at the client boundary.
globalThis.onmessage = async (event: MessageEvent<Request>) => {
  const request = event.data;
  let response: Response;
  try {
    if (request.operation === "open") {
      if (session) throw new Error("Session is already open");
      session = (await loadEngine(request.wasm)).openText(request.text);
    } else {
      if (!session) throw new Error("Session is not open");
      switch (request.operation) {
        case "replace":
          session.replace(request.start, request.end, request.text);
          break;
        case "undo":
          session.undo();
          break;
        case "read":
          break;
      }
    }
    if (!session) throw new Error("Session was not initialized");
    response = { id: request.id, ok: true, text: session.read() };
  } catch (error) {
    response = {
      id: request.id,
      ok: false,
      error: error instanceof Error ? error.message : String(error),
    };
  }
  globalThis.postMessage(response);
};
