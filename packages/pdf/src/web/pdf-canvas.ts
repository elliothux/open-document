import type { PdfLayout } from "../core/pdf.js";
import { CanvasSurface } from "@open-document/web-core/canvas-surface";
import { documentFailure } from "@open-document/web-core/connection";
import {
  imageBitmapFromPixels,
  materializeImage,
} from "@open-document/web-core/image";
import type { PdfClient } from "./pdf.js";

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
          const decoded = await materializeImage({
            kind: "encoded",
            bytes: resource.bytes,
            header: resource.header,
          });
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
