import type { FoundationSession } from "../core/foundation.js";
import type { DocxInkRequest } from "./protocol-docx-ink.js";

export function inkOperation(
  foundation: FoundationSession,
  request: DocxInkRequest,
): unknown {
  const { revision, layoutId, page } = request;
  if (request.action === "preview")
    return foundation.previewInk(revision, layoutId, page, request.stroke);
  if (request.action === "insert")
    return foundation.insertInk(
      revision,
      layoutId,
      page,
      request.stroke,
      request.profile,
    );
  return foundation.eraseInk(revision, layoutId, page, request.x, request.y);
}
