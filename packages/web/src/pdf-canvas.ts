import type { PdfLayout } from "@open-document/wasm/pdf";
import { CanvasSurface } from "./canvas-surface.js";
import { decodeImage } from "./image.js";
import type { PdfClient } from "./pdf.js";

export class PdfCanvas extends CanvasSurface {
  private disposed = false;
  async prepare(client: PdfClient, layout: PdfLayout): Promise<void> {
    for (const image of this.images.values()) image.close();
    this.images.clear();
    try {
      for (const key of layout.images) {
        let resource = await client.execute({
          operation: "imagePdf",
          layoutId: layout.id,
          key,
        });
        if (resource.kind === "jpeg") {
          const decoded = await decodeImage(resource.bytes);
          try {
            resource = await client.execute({
              operation: "decodedImagePdf",
              layoutId: layout.id,
              key,
              width: decoded.bitmap.width,
              height: decoded.bitmap.height,
              bytes: decoded.rgba,
            });
          } finally {
            decoded.bitmap.close();
          }
        }
        const rgba = new Uint8ClampedArray(resource.bytes.length);
        rgba.set(resource.bytes);
        const bitmap = await createImageBitmap(
          new ImageData(rgba, resource.width, resource.height),
        );
        if (this.disposed) {
          bitmap.close();
          throw new Error("PDF canvas is disposed");
        }
        this.images.set(key, bitmap);
      }
    } catch (error) {
      for (const bitmap of this.images.values()) bitmap.close();
      this.images.clear();
      throw error;
    }
  }
  selection(quads: number[][], scale: number): void {
    const context = this.clearOverlay(scale);
    context.fillStyle = "rgba(37,99,235,0.25)";
    for (const quad of quads) {
      context.beginPath();
      context.moveTo(quad[0]!, quad[1]!);
      for (let i = 2; i < 8; i += 2) context.lineTo(quad[i]!, quad[i + 1]!);
      context.closePath();
      context.fill();
    }
  }
  override dispose(): void {
    this.disposed = true;
    super.dispose();
  }
}
