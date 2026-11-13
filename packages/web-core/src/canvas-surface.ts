import { CanvasRenderer } from "./drawing.js";
import { documentFailure } from "./connection.js";
import type {
  DrawingBatch,
  DrawingRegion,
  DrawCommand,
} from "@open-document/wasm/abi/drawing";

interface PaintedRegion {
  region: DrawingRegion;
  outlines: DrawingBatch["outlines"];
  images: Map<string, ImageBitmap>;
  scale: number;
}

/** Canvas size, DPR, overlays and renderer resources shared by format hosts. */
export class CanvasSurface {
  readonly canvas = document.createElement("canvas");
  private overlayCanvas: HTMLCanvasElement | undefined;
  private readonly renderer: CanvasRenderer;
  protected readonly images = new Map<string, ImageBitmap>();
  protected readonly imagePixels = new Map<string, Uint8Array>();
  protected readonly imageColors = new Map<string, ImageBitmap>();
  protected readonly imageKeys = new Map<string, string>();
  private key: string | undefined;
  private painted: PaintedRegion | undefined;
  private rasterDpr: number | undefined;
  private closed = false;

  constructor(private readonly patchText = false) {
    this.renderer = new CanvasRenderer(
      undefined,
      this.imagePixels,
      this.imageColors,
    );
    this.canvas.setAttribute("aria-hidden", "true");
    this.canvas.style.display = "block";
  }

  /** Takes ownership even when decoding completes after disposal. */
  protected cacheImage(
    identity: string,
    bitmap: ImageBitmap,
    pixels?: Uint8Array,
    colors?: ImageBitmap,
  ): void {
    if (this.closed || this.images.has(identity)) {
      bitmap.close();
      colors?.close();
      if (this.closed) throw new Error("Canvas surface is disposed");
      return;
    }
    this.images.set(identity, bitmap);
    if (pixels) this.imagePixels.set(identity, pixels);
    if (colors) this.imageColors.set(identity, colors);
  }

  protected retainImages(identities: ReadonlySet<string>): void {
    for (const [identity, bitmap] of this.images) {
      if (identities.has(identity)) continue;
      bitmap.close();
      this.images.delete(identity);
      this.imagePixels.delete(identity);
      this.imageColors.get(identity)?.close();
      this.imageColors.delete(identity);
    }
  }

  protected retainImageKeys(keys: ReadonlySet<string>): void {
    for (const key of this.imageKeys.keys())
      if (!keys.has(key)) this.imageKeys.delete(key);
    this.retainImages(new Set(this.imageKeys.values()));
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
    liveImages?: ReadonlyMap<DrawCommand, CanvasImageSource>,
  ): number {
    if (this.closed) throw new Error("Canvas surface is disposed");
    const page = layout.regions[index];
    if (!page) throw new Error("Unknown page");
    if (!Number.isFinite(zoom) || zoom < 0.25 || zoom > 4)
      throw new Error("Invalid zoom");
    const cssScale = (zoom * 96) / 72;
    const dpr = window.devicePixelRatio;
    if (!Number.isFinite(dpr) || dpr <= 0) throw new Error("Invalid DPR");
    let scale = cssScale * dpr;
    let width = Math.ceil(page.width * scale);
    let height = Math.ceil(page.height * scale);
    const pixelLimit = this.overlayCanvas ? 8388608 : 16777216;
    if (width * height > pixelLimit) {
      // Preserve CSS geometry and lower raster density to fit both canvases.
      const fit = Math.sqrt(pixelLimit / width / height);
      width = Math.max(1, Math.floor(width * fit));
      height = Math.max(1, Math.floor(height * fit));
      scale = Math.min(scale, width / page.width, height / page.height);
    }
    if (!(width * height > 0 && width * height <= pixelLimit))
      throw new Error("Preview canvas exceeds budget");
    const key = `${layout.id}:${index}:${zoom}:${dpr}:${page.glyphRaster ?? "integer"}`;
    if (this.key === key && !liveImages?.size) return cssScale;
    const previous = this.painted;
    this.painted = undefined;
    const sameRaster =
      this.canvas.width === width && this.canvas.height === height;
    const canvases = this.overlayCanvas
      ? [this.canvas, this.overlayCanvas]
      : [this.canvas];
    for (const canvas of canvases) {
      if (canvas.width !== width) canvas.width = width;
      if (canvas.height !== height) canvas.height = height;
      canvas.style.width = `${page.width * cssScale}px`;
      canvas.style.height = `${page.height * cssScale}px`;
    }
    this.key = undefined;
    this.rasterDpr = scale / cssScale;
    try {
      const context = this.canvas.getContext("2d");
      if (!context) throw new Error("Canvas is unavailable");
      const damage =
        previous && sameRaster && !liveImages?.size && previous.scale === scale
          ? this.renderer.textDamage(
              previous.region,
              page,
              previous.outlines,
              layout.outlines,
              scale,
              (key) => previous.images.get(key) === this.images.get(key),
            )
          : undefined;
      if (!damage || (damage.width > 0 && damage.height > 0)) {
        context.save();
        try {
          context.resetTransform();
          if (damage) {
            const clip = new Path2D();
            clip.rect(damage.x, damage.y, damage.width, damage.height);
            context.clip(clip);
            context.clearRect(damage.x, damage.y, damage.width, damage.height);
          } else context.clearRect(0, 0, width, height);
          context.setTransform(scale, 0, 0, scale, 0, 0);
          this.renderer.drawRegion(
            context,
            layout,
            index,
            this.images,
            liveImages,
            true,
          );
        } finally {
          context.restore();
        }
      }
      if (this.overlayCanvas) this.clearOverlay(cssScale);
    } catch (error) {
      throw documentFailure("draw", error);
    }
    this.key = liveImages?.size ? undefined : key;
    if (this.patchText && !liveImages?.size)
      this.painted = {
        region: page,
        outlines: layout.outlines,
        images: new Map(this.images),
        scale,
      };
    return cssScale;
  }

  clearOverlay(cssScale: number): CanvasRenderingContext2D {
    if (this.closed) throw new Error("Canvas surface is disposed");
    const context = this.overlay.getContext("2d");
    if (!context) throw new Error("Canvas is unavailable");
    context.resetTransform();
    context.clearRect(0, 0, this.overlay.width, this.overlay.height);
    const scale = cssScale * (this.rasterDpr ?? window.devicePixelRatio);
    context.setTransform(scale, 0, 0, scale, 0, 0);
    return context;
  }

  drawOverlay(layout: DrawingBatch, cssScale: number): void {
    this.renderer.drawRegion(
      this.clearOverlay(cssScale),
      layout,
      0,
      this.images,
    );
  }

  async exportImage(
    layout: DrawingBatch,
    index: number,
    scale: number,
    outputBytes: number,
    maxOutputBytes: number,
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
      outputBytes > maxOutputBytes
    )
      throw new Error("Invalid image output budget");
    const blob = await this.encodeImage(
      layout,
      index,
      scale,
      outputBytes,
      format,
    );
    const bytes = new Uint8Array(await blob.arrayBuffer());
    if (this.closed) throw new Error("Canvas surface is disposed");
    return bytes;
  }

  previewImage(
    layout: DrawingBatch,
    index: number,
    outputBytes = 1_048_576,
  ): Promise<Blob> {
    const page = layout.regions[index];
    if (!page) throw new Error("Unknown page");
    const scale = Math.min(1 / 3, 256 / Math.max(page.width, page.height));
    return this.encodeImage(layout, index, scale, outputBytes, "png");
  }

  private async encodeImage(
    layout: DrawingBatch,
    index: number,
    scale: number,
    outputBytes: number,
    format: "png" | "jpeg",
  ): Promise<Blob> {
    if (this.closed) throw new Error("Canvas surface is disposed");
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
      return blob;
    } finally {
      canvas.width = canvas.height = 0;
    }
  }

  dispose(): void {
    if (this.closed) return;
    this.closed = true;
    this.painted = undefined;
    this.key = undefined;
    this.canvas.width = this.canvas.height = 0;
    if (this.overlayCanvas)
      this.overlayCanvas.width = this.overlayCanvas.height = 0;
    this.renderer.dispose();
    this.retainImages(new Set());
    this.imageKeys.clear();
  }
}
