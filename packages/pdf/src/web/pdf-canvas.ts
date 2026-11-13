import type { PdfLayout } from "../core/pdf.js";
import { CanvasSurface } from "@open-document/web-core/canvas-surface";
import { documentFailure } from "@open-document/web-core/connection";
import {
  decodeImage,
  imageBitmapFromPixels,
} from "@open-document/web-core/image";
import type { PdfClient } from "./pdf.js";
import { sampleJpeg } from "./pdf-jpeg-samples.js";

export class PdfCanvas extends CanvasSurface {
  async prepare(client: PdfClient, layout: PdfLayout): Promise<void> {
    this.retainImages(new Set());
    try {
      for (const key of layout.images) {
        let resource = await client.execute({
          operation: "imagePdf",
          layoutId: layout.id,
          key,
        });
        if (resource.kind === "jpeg") {
          const { width, height, header, bytes } = resource;
          const size =
            "width" in header &&
            (width !== header.width || height !== header.height)
              ? { width, height }
              : undefined;
          let pixels: Uint8Array;
          if (resource.sourceSamples) {
            pixels = await sampleJpeg(bytes, header, width, height);
          } else {
            const decoded = await decodeImage(bytes, header, undefined, size);
            pixels = decoded.rgba;
            decoded.bitmap.close();
          }
          resource = await client.execute({
            operation: "decodedImagePdf",
            layoutId: layout.id,
            key,
            width,
            height,
            bytes: pixels,
          });
        }
        const bitmap = await imageBitmapFromPixels(
          resource.width,
          resource.height,
          resource.bytes,
        );
        this.cacheImage(key, bitmap);
      }
    } catch (error) {
      this.retainImages(new Set());
      throw documentFailure("image", error);
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
}
