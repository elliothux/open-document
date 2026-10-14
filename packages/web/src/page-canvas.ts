import type { FoundationClient } from "./foundation.js";
import { CanvasRenderer } from "./drawing.js";
import type { PageLayout } from "@open-document/wasm/preview";
import { imageDimensions } from "./image.js";

/** Page drawing and decoded resources shared by preview and editing hosts. */
export class PageCanvas {
  readonly canvas = document.createElement("canvas");
  private overlayCanvas: HTMLCanvasElement | undefined;
  private readonly renderer = new CanvasRenderer();
  private readonly images = new Map<string, ImageBitmap>();
  private key: string | undefined;
  private closed = false;

  private constructor() {
    this.canvas.setAttribute("aria-hidden", "true");
    this.canvas.style.display = "block";
  }

  get overlay(): HTMLCanvasElement {
    if (this.closed) throw new Error("Page canvas is disposed");
    if (this.overlayCanvas) return this.overlayCanvas;
    const overlay = document.createElement("canvas");
    overlay.setAttribute("aria-hidden", "true");
    Object.assign(overlay.style, {
      position: "absolute",
      left: "0",
      top: "0",
      pointerEvents: "none",
    });
    this.overlayCanvas = overlay;
    return overlay;
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

  draw(layout: PageLayout, index: number, zoom: number): number {
    if (this.closed) throw new Error("Page canvas is disposed");
    const page = layout.pages[index];
    if (!page) throw new Error("Unknown page");
    if (!Number.isFinite(zoom) || zoom < 0.25 || zoom > 4)
      throw new Error("Invalid zoom");
    const cssScale = (zoom * 96) / 72;
    const dpr = window.devicePixelRatio;
    if (!Number.isFinite(dpr) || dpr <= 0) throw new Error("Invalid DPR");
    const scale = cssScale * dpr;
    const width = Math.ceil(page.width * scale);
    const height = Math.ceil(page.height * scale);
    if (width * height * (this.overlayCanvas ? 2 : 1) > 16777216)
      throw new Error("Preview canvas exceeds budget");
    const key = `${layout.id}:${index}:${zoom}:${dpr}`;
    if (this.key === key) return cssScale;
    const canvases = this.overlayCanvas
      ? [this.canvas, this.overlayCanvas]
      : [this.canvas];
    for (const canvas of canvases) {
      if (canvas.width !== width) canvas.width = width;
      if (canvas.height !== height) canvas.height = height;
      canvas.style.width = `${page.width * cssScale}px`;
      canvas.style.height = `${page.height * cssScale}px`;
    }
    const context = this.canvas.getContext("2d");
    if (!context) throw new Error("Canvas is unavailable");
    context.resetTransform();
    context.clearRect(0, 0, width, height);
    context.setTransform(scale, 0, 0, scale, 0, 0);
    this.key = undefined;
    this.renderer.drawPage(context, layout, index, this.images);
    if (this.overlayCanvas) this.clearOverlay(cssScale);
    this.key = key;
    return cssScale;
  }

  clearOverlay(cssScale: number): CanvasRenderingContext2D {
    if (this.closed) throw new Error("Page canvas is disposed");
    const context = this.overlay.getContext("2d");
    if (!context) throw new Error("Canvas is unavailable");
    context.resetTransform();
    context.clearRect(0, 0, this.overlay.width, this.overlay.height);
    const scale = cssScale * window.devicePixelRatio;
    context.setTransform(scale, 0, 0, scale, 0, 0);
    return context;
  }

  dispose(): void {
    if (this.closed) return;
    this.closed = true;
    this.key = undefined;
    this.canvas.width = this.canvas.height = 0;
    if (this.overlayCanvas)
      this.overlayCanvas.width = this.overlayCanvas.height = 0;
    this.renderer.dispose();
    for (const image of this.images.values()) image.close();
    this.images.clear();
  }
}
