import { PdfCanvas } from "./pdf-canvas.js";
import type { PdfClient } from "./pdf.js";

/** Render one page at a time with the same drawing path and a shared budget. */
export async function pdfPageImages(
  client: PdfClient,
  revision: number,
  pages: readonly string[],
  profile: Record<string, string>,
  format: "png" | "jpeg",
  scale: number,
  outputBytes: number,
  assertOpen: () => void,
): Promise<Uint8Array[]> {
  if (
    !pages.length ||
    pages.length > 1024 ||
    new Set(pages).size !== pages.length
  )
    throw new Error("Choose distinct PDF output pages");
  if (
    !Number.isInteger(outputBytes) ||
    outputBytes < 1 ||
    outputBytes > 67108864
  )
    throw new Error("Invalid PDF output budget");
  if (format !== "png" && format !== "jpeg")
    throw new Error("Unsupported PDF image format");
  const output: Uint8Array[] = [];
  let remaining = outputBytes;
  for (const page of pages) {
    assertOpen();
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
      if (!layout.displayComplete)
        throw new Error(
          "PDF page drawing is incomplete; image export is protected",
        );
      await surface.prepare(client, layout);
      const bytes = await surface.exportImage(
        layout,
        0,
        scale,
        remaining,
        format,
      );
      output.push(bytes);
      remaining -= bytes.length;
      assertOpen();
    } finally {
      surface.dispose();
      if (!layout.reused)
        await client.execute({
          operation: "releasePdfView",
          layoutId: layout.id,
        });
    }
  }
  return output;
}
