import type { FoundationSession } from "@open-document/wasm/foundation";
import type { Request } from "./protocol.js";

export function selectionOperation(
  session: FoundationSession,
  request: Extract<
    Request,
    { operation: "selectDocx" | "selectAllDocx" | "selectedText" }
  >,
): unknown {
  switch (request.operation) {
    case "selectDocx":
      return session.selectDocx(request.revision, request.selection);
    case "selectAllDocx":
      return session.selectAllDocx(request.revision);
    case "selectedText":
      return session.selectedText(
        request.revision,
        request.selection,
        request.cut,
      );
  }
}
