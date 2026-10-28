import { errorResponse, type Response } from "./protocol.js";

/** One ordered dispatch queue per document Worker. */
export function serveWorker<Operation extends { operation: string }>(
  dispatch: (request: Operation) => Promise<unknown>,
): void {
  let busy = false;
  globalThis.onmessage = async (
    event: MessageEvent<Operation & { id: number }>,
  ) => {
    const request = event.data;
    if (busy) {
      globalThis.postMessage({
        id: request.id,
        ok: false,
        error: "Await the previous operation",
      });
      return;
    }
    busy = true;
    let response: Response;
    try {
      response = { id: request.id, ok: true, value: await dispatch(request) };
    } catch (error) {
      response = errorResponse(request.id, error);
    } finally {
      busy = false;
    }
    globalThis.postMessage(response);
  };
}
