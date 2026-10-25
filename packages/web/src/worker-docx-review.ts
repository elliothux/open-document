import type { FoundationSession } from "@open-document/wasm/foundation";
import type { Request } from "./protocol.js";

type ReviewRequest = Extract<
  Request,
  {
    operation:
      | "docxTracking"
      | "setDocxTracking"
      | "docxRevisions"
      | "docxRevisionGeometry"
      | "resolveDocxRevisions";
  }
>;

export function reviewOperation(
  foundation: FoundationSession,
  request: ReviewRequest,
): unknown {
  switch (request.operation) {
    case "docxTracking":
      return foundation.tracking(request.revision);
    case "setDocxTracking":
      return foundation.setTracking(request.revision, request.author);
    case "docxRevisions":
      return foundation.revisions(request.revision);
    case "docxRevisionGeometry":
      return foundation.revisionGeometry(
        request.revision,
        request.layoutId,
        request.revisionId,
      );
    case "resolveDocxRevisions":
      return foundation.resolveRevisions(request.revision, request.change);
  }
}
