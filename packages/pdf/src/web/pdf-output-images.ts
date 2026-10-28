import { PdfCanvas } from "./pdf-canvas.js";
import type { PdfClient } from "./pdf.js";

/** Reuse the existing validated decoder cache without changing active selection. */
export async function preparePdfOutputImages(
  client: PdfClient,
  revision: number,
  pages: readonly string[],
  profile: Record<string, string>,
  requireComplete = true,
): Promise<void> {
  if (
    !pages.length ||
    pages.length > 1024 ||
    new Set(pages).size !== pages.length
  )
    throw new Error("Choose bounded, distinct PDF pages");
  for (const page of pages) {
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
      if (requireComplete && !layout.displayComplete)
        throw new Error(
          "PDF drawing is incomplete; structured output is protected",
        );
      await surface.prepare(client, layout);
    } finally {
      surface.dispose();
      if (!layout.reused)
        await client.execute({
          operation: "releasePdfView",
          layoutId: layout.id,
        });
    }
  }
}
