import type { FoundationClient } from "./foundation.js";
import { CanvasSurface } from "./canvas-surface.js";
import { decodeImage } from "./image.js";
import type {
  DocxSelectionGeometry,
  DocxHit,
} from "@open-document/wasm/foundation";

/** DOCX image preparation stays with its document host. */
export class PageCanvas extends CanvasSurface {
  drawSelection(
    page: number,
    scale: number,
    geometry: DocxSelectionGeometry | undefined,
    caret: DocxHit | undefined,
  ): void {
    const context = this.clearOverlay(scale);
    context.fillStyle = "rgba(30, 100, 220, 0.25)";
    for (const rect of geometry?.rects ?? []) {
      if (rect.page === page)
        context.fillRect(rect.x, rect.y, rect.width, rect.height);
    }
    if (caret) {
      context.fillStyle = "#174ca0";
      context.fillRect(caret.x, caret.y, 1 / scale, caret.height);
    }
  }
  static async create(
    client: FoundationClient,
    signal?: AbortSignal,
  ): Promise<PageCanvas> {
    const surface = new PageCanvas();
    try {
      signal?.throwIfAborted();
      const flow = await client.flow();
      const paragraphs = [
        ...flow.paragraphs,
        ...flow.headers.flat(),
        ...flow.tables.flatMap((table) => table.rows.flat(2)),
      ];
      const prepared = new Set<string>();
      for (const span of paragraphs.flatMap((paragraph) => paragraph.spans)) {
        if (!span.image || prepared.has(span.image.key)) continue;
        const { bitmap, rgba } = await decodeImage(
          await client.imageBytes(span.image.key),
          signal,
        );
        try {
          const key = await client.addImage(
            span.image.key,
            bitmap.width,
            bitmap.height,
            rgba,
          );
          if (surface.images.has(key)) bitmap.close();
          else surface.images.set(key, bitmap);
          prepared.add(span.image.key);
        } catch (error) {
          bitmap.close();
          throw error;
        }
      }
      signal?.throwIfAborted();
      return surface;
    } catch (error) {
      surface.dispose();
      throw error;
    }
  }
}
