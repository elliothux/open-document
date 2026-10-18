import type {
  PptxGeometry,
  PptxPoint,
  PptxLayout,
} from "@open-document/wasm/pptx";
import { CanvasSurface } from "./canvas-surface.js";
import { decodeImage } from "./image.js";
import type { PptxClient } from "./pptx.js";

export class PresentationCanvas extends CanvasSurface {
  point(event: MouseEvent, scale: number): PptxPoint {
    const rect = this.canvas.getBoundingClientRect();
    return {
      x: (event.clientX - rect.left) / scale,
      y: (event.clientY - rect.top) / scale,
    };
  }
  async exportSlideImage(
    layout: PptxLayout,
    current: { revision: number; slide: string },
    scale: number,
    outputBytes: number,
    format: "png" | "jpeg",
  ): Promise<Uint8Array> {
    if (layout.revision !== current.revision || layout.slide !== current.slide)
      throw new Error("Slide layout is stale; refresh before exporting");
    return this.exportImage(layout, 0, scale, outputBytes, format);
  }
  async exportPageImages(
    client: PptxClient,
    revision: number,
    profile: Record<string, string>,
    scale: number,
    outputBytes: number,
    hidden: boolean,
    assertOpen: () => void,
    format: "png" | "jpeg",
  ): Promise<Uint8Array[]> {
    if (
      !Number.isInteger(outputBytes) ||
      outputBytes < 1 ||
      outputBytes > 67108864
    )
      throw new Error("Invalid image output budget");
    try {
      await this.prepare(client, true, hidden);
      assertOpen();
      const layout = await client.execute({
        operation: "printLayoutPptx",
        revision,
        all: true,
        hidden,
        profile,
      });
      assertOpen();
      if (layout.revision !== revision)
        throw new Error("Presentation changed before exporting");
      const buffers: Uint8Array[] = [];
      let remaining = outputBytes;
      for (const index of layout.regions.keys()) {
        assertOpen();
        if (remaining === 0) throw new Error("Image pages exceed byte budget");
        const bytes = await this.exportImage(
          layout,
          index,
          scale,
          remaining,
          format,
        );
        assertOpen();
        remaining -= bytes.byteLength;
        buffers.push(bytes);
      }
      return buffers;
    } finally {
      await this.prepare(client);
    }
  }
  private readonly keys = new Map<string, string>();
  async prepare(
    client: PptxClient,
    all = false,
    hidden = false,
  ): Promise<void> {
    const keys = await client.execute({
      operation: "imageKeysPptx",
      all,
      hidden,
    });
    for (const key of this.keys.keys())
      if (!keys.includes(key)) this.keys.delete(key);
    const retained = new Set(this.keys.values());
    for (const [identity, bitmap] of this.images)
      if (!retained.has(identity)) {
        bitmap.close();
        this.images.delete(identity);
      }
    for (const key of keys) {
      if (this.keys.has(key)) continue;
      const bytes = await client.execute({ operation: "imageBytesPptx", key });
      const { bitmap, rgba } = await decodeImage(bytes);
      try {
        const { key: identity } = await client.execute({
          operation: "imagePptx",
          key,
          width: bitmap.width,
          height: bitmap.height,
          bytes: rgba,
        });
        if (this.images.has(identity)) bitmap.close();
        else this.images.set(identity, bitmap);
        this.keys.set(key, identity);
      } catch (error) {
        bitmap.close();
        throw error;
      }
    }
  }
  drawSelection(
    geometry: PptxGeometry,
    scale: number,
    input: HTMLTextAreaElement,
  ): void {
    const context = this.clearOverlay(scale);
    const polygon = (points: PptxPoint[]) => {
      context.beginPath();
      for (const [i, point] of points.entries())
        if (i === 0) context.moveTo(point.x, point.y);
        else context.lineTo(point.x, point.y);
      context.closePath();
    };
    context.fillStyle = "rgba(59,130,246,0.25)";
    for (const rect of geometry.rects) {
      polygon(rect);
      context.fill();
    }
    context.strokeStyle = "#2563eb";
    context.lineWidth = 1 / scale;
    for (const outline of geometry.outlines) {
      polygon(outline);
      context.stroke();
    }
    if (geometry.outline.length && geometry.outlines.length !== 1) {
      polygon(geometry.outline);
      context.stroke();
    }
    context.fillStyle = "#ffffff";
    for (const point of geometry.handles) {
      const size = 6 / scale;
      context.fillRect(point.x - size / 2, point.y - size / 2, size, size);
      context.strokeRect(point.x - size / 2, point.y - size / 2, size, size);
    }

    const caret = geometry.caret;
    if (caret) {
      input.style.left = `${caret.x * scale}px`;
      input.style.top = `${caret.y * scale}px`;
      input.style.height = `${caret.height * scale}px`;
      context.beginPath();
      context.moveTo(caret.x, caret.y);
      context.lineTo(caret.endX, caret.endY);
      context.stroke();
    }
  }
  async exportPdf(
    client: PptxClient,
    revision: number,
    profile: Record<string, string>,
    all: boolean,
    hidden: boolean,
    outputBytes: number,
  ): Promise<Uint8Array> {
    try {
      await this.prepare(client, all, hidden);
      return await client.execute({
        operation: "exportPptxPdf",
        revision,
        all,
        hidden,
        outputBytes,
        profile,
      });
    } finally {
      await this.prepare(client);
    }
  }
  override dispose(): void {
    this.keys.clear();
    super.dispose();
  }
}
