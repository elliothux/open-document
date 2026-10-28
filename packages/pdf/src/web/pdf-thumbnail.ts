import { PdfCanvas } from "./pdf-canvas.js";
import type { PdfClient } from "./pdf.js";

/** Thumbnail drawing borrows retained views and releases only views it creates. */
export async function pdfThumbnail(
  client: PdfClient,
  revision: number,
  page: string,
  profile: Record<string, string>,
): Promise<Blob> {
  const layout = await client.execute({
    operation: "renderPdfPage",
    revision,
    page,
    profile,
    activate: false,
    reuse: true,
  });
  const surface = new PdfCanvas();
  try {
    await surface.prepare(client, layout);
    surface.draw(layout, 0, 0.25);
    const blob = await new Promise<Blob>((resolve, reject) =>
      surface.canvas.toBlob(
        (value) =>
          value
            ? resolve(value)
            : reject(new Error("PDF thumbnail encoding failed")),
        "image/png",
      ),
    );
    if (blob.size > 1048576) throw new Error("PDF thumbnail exceeds budget");
    return blob;
  } finally {
    surface.dispose();
    if (!layout.reused)
      await client.execute({
        operation: "releasePdfView",
        layoutId: layout.id,
      });
  }
}
