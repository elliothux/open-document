import { CanvasRenderer } from "./drawing.js";
import type { DrawingBatch } from "@open-document/wasm/drawing";

/** Canvas size, DPR, overlays and renderer resources shared by format hosts. */
export class CanvasSurface {
  readonly canvas = document.createElement("canvas");
  private overlayCanvas: HTMLCanvasElement | undefined;
  private readonly renderer = new CanvasRenderer();
  protected readonly images = new Map<string, ImageBitmap>();
  private key: string | undefined;
  private closed = false;

  constructor() {
    this.canvas.setAttribute("aria-hidden", "true");
    this.canvas.style.display = "block";
  }

  get overlay(): HTMLCanvasElement {
    if (this.closed) throw new Error("Canvas surface is disposed");
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
    this.key = undefined;
    return overlay;
  }

  draw(
    layout: DrawingBatch & { id: number },
    index: number,
    zoom: number,
  ): number {
    if (this.closed) throw new Error("Canvas surface is disposed");
    const page = layout.regions[index];
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
    this.renderer.drawRegion(context, layout, index, this.images);
    if (this.overlayCanvas) this.clearOverlay(cssScale);
    this.key = key;
    return cssScale;
  }

  clearOverlay(cssScale: number): CanvasRenderingContext2D {
    if (this.closed) throw new Error("Canvas surface is disposed");
    const context = this.overlay.getContext("2d");
    if (!context) throw new Error("Canvas is unavailable");
    context.resetTransform();
    context.clearRect(0, 0, this.overlay.width, this.overlay.height);
    const scale = cssScale * window.devicePixelRatio;
    context.setTransform(scale, 0, 0, scale, 0, 0);
    return context;
  }

  async exportImage(
    layout: DrawingBatch,
    index: number,
    scale: number,
    outputBytes: number,
    format: "png" | "jpeg" = "png",
  ): Promise<Uint8Array> {
    if (this.closed) throw new Error("Canvas surface is disposed");
    if (format !== "png" && format !== "jpeg")
      throw new Error("Unsupported image output format");
    if (!Number.isFinite(scale) || scale < 0.25 || scale > 4)
      throw new Error(
        "Image scale must be between 0.25 and 4 pixels per point",
      );
    if (
      !Number.isInteger(outputBytes) ||
      outputBytes < 1 ||
      outputBytes > 67108864
    )
      throw new Error("Invalid image output budget");
    const page = layout.regions[index];
    if (!page) throw new Error("Unknown page");
    const width = Math.ceil(page.width * scale),
      height = Math.ceil(page.height * scale);
    const retainedPixels =
      this.canvas.width * this.canvas.height +
      (this.overlayCanvas
        ? this.overlayCanvas.width * this.overlayCanvas.height
        : 0);
    if (
      !Number.isSafeInteger(width) ||
      !Number.isSafeInteger(height) ||
      width <= 0 ||
      height <= 0 ||
      width * height + retainedPixels > 16777216
    )
      throw new Error("Image canvas exceeds pixel budget");
    const canvas = document.createElement("canvas");
    try {
      canvas.width = width;
      canvas.height = height;
      const context = canvas.getContext("2d");
      if (!context) throw new Error("Canvas is unavailable");
      if (format === "jpeg") {
        context.fillStyle = "#ffffff";
        context.fillRect(0, 0, width, height);
      }
      context.setTransform(scale, 0, 0, scale, 0, 0);
      this.renderer.drawRegion(context, layout, index, this.images);
      const blob = await new Promise<Blob>((resolve, reject) =>
        canvas.toBlob(
          (value) => {
            if (value?.type === `image/${format}`) resolve(value);
            else reject(new Error("Image encoding failed"));
          },
          `image/${format}`,
          0.92,
        ),
      );
      if (this.closed) throw new Error("Canvas surface is disposed");
      if (blob.size > outputBytes)
        throw new Error("Image output exceeds byte budget");
      const bytes = new Uint8Array(await blob.arrayBuffer());
      if (this.closed) throw new Error("Canvas surface is disposed");
      return bytes;
    } finally {
      canvas.width = canvas.height = 0;
    }
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
