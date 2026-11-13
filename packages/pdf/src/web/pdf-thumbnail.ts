import { PdfCanvas } from "./pdf-canvas.js";
import type { PdfClient } from "./pdf.js";

/** Thumbnail drawing borrows retained views and releases only views it creates. */
export async function pdfThumbnail(
  client: PdfClient,
  revision: number,
  page: string,
  profile: Record<string, string>,
  signal?: AbortSignal,
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
    signal?.throwIfAborted();
    await surface.prepare(client, layout);
    signal?.throwIfAborted();
    return await surface.previewImage(layout, 0);
  } finally {
    surface.dispose();
    if (!layout.reused)
      await client.execute({
        operation: "releasePdfView",
        layoutId: layout.id,
      });
  }
}
