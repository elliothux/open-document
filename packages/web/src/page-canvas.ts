import type { FoundationClient } from "./foundation.js";
import { CanvasSurface } from "./canvas-surface.js";
import { imageDimensions } from "./image.js";

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
        signal?.throwIfAborted();
        const bytes = await client.imageBytes(span.image.key);
        const declared = imageDimensions(bytes);
        const bitmap = await createImageBitmap(
          new Blob([new Uint8Array(bytes).buffer]),
          { imageOrientation: "none" },
        );
        try {
          signal?.throwIfAborted();
          if (
            bitmap.width * bitmap.height > 4194304 ||
            bitmap.width > 4096 ||
            bitmap.height > 4096
          )
            throw new Error("Decoded image exceeds budget");
          if (
            bitmap.width !== declared.width ||
            bitmap.height !== declared.height
          )
            throw new Error("Decoded image dimensions differ from its header");
          const canvas = document.createElement("canvas");
          canvas.width = bitmap.width;
          canvas.height = bitmap.height;
          try {
            const context = canvas.getContext("2d");
            if (!context) throw new Error("Canvas is unavailable");
            context.drawImage(bitmap, 0, 0);
            const rgba = context.getImageData(
              0,
              0,
              canvas.width,
              canvas.height,
            ).data;
            const key = await client.addImage(
              span.image.key,
              bitmap.width,
              bitmap.height,
              new Uint8Array(rgba),
            );
            const previous = surface.images.get(key);
            if (previous) bitmap.close();
            else surface.images.set(key, bitmap);
            prepared.add(span.image.key);
          } finally {
            canvas.width = canvas.height = 0;
          }
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
