import type { FoundationClient } from "./foundation.js";
import { CanvasSurface } from "./canvas-surface.js";
import { decodeImage } from "./image.js";

/** DOCX image preparation stays with its document host. */
export class PageCanvas extends CanvasSurface {
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
