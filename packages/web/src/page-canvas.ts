import { type FoundationClient, OutlineCanvas } from "./foundation.js";
import type { PageLayout } from "@open-document/wasm/preview";
import { imageDimensions } from "./image.js";

/** Page drawing and decoded resources shared by preview and editing hosts. */
export class PageCanvas {
  readonly canvas = document.createElement("canvas");
  private readonly renderer = new OutlineCanvas();
  private readonly images = new Map<string, ImageBitmap>();

  private constructor() {
    this.canvas.setAttribute("aria-hidden", "true");
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
        ...flow.tables.flatMap((table) => table.rows.flat(2)),
      ];
      for (const span of paragraphs.flatMap((paragraph) => paragraph.spans)) {
        if (!span.image || surface.images.has(span.image.key)) continue;
        signal?.throwIfAborted();
        const bytes = await client.imageBytes(span.image.key);
        const declared = imageDimensions(bytes);
        const bitmap = await createImageBitmap(
          new Blob([new Uint8Array(bytes).buffer]),
          { imageOrientation: "none" },
        );
        surface.images.set(span.image.key, bitmap);
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
          await client.addImage(
            span.image.key,
            bitmap.width,
            bitmap.height,
            new Uint8Array(rgba),
          );
        } finally {
          canvas.width = canvas.height = 0;
        }
      }
      signal?.throwIfAborted();
      return surface;
    } catch (error) {
      surface.dispose();
      throw error;
    }
  }

  draw(layout: PageLayout, index: number, zoom: number): number {
    const page = layout.pages[index];
    if (!page) throw new Error("Unknown page");
    if (!Number.isFinite(zoom) || zoom < 0.25 || zoom > 4)
      throw new Error("Invalid zoom");
    const cssScale = (zoom * 96) / 72;
    const scale = cssScale * window.devicePixelRatio;
    const width = Math.ceil(page.width * scale);
    const height = Math.ceil(page.height * scale);
    if (width * height > 16777216)
      throw new Error("Preview canvas exceeds budget");
    this.canvas.width = width;
    this.canvas.height = height;
    this.canvas.style.width = `${page.width * cssScale}px`;
    this.canvas.style.height = `${page.height * cssScale}px`;
    const context = this.canvas.getContext("2d");
    if (!context) throw new Error("Canvas is unavailable");
    context.scale(scale, scale);
    this.renderer.drawPage(context, layout, index, this.images);
    return cssScale;
  }

  dispose(): void {
    this.canvas.width = this.canvas.height = 0;
    this.renderer.dispose();
    for (const image of this.images.values()) image.close();
    this.images.clear();
  }
}
