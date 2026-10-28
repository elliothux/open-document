import type { PdfRedactionPreview } from "../core/pdf.js";
import type { PdfCanvas } from "./pdf-canvas.js";

/** Preview overlays are candidates only; no source pixels or text are changed. */
export function drawRedactionPreview(
  surface: PdfCanvas,
  preview: PdfRedactionPreview,
  page: string,
  scale: number,
): void {
  const context = surface.clearOverlay(scale);
  context.save();
  context.globalAlpha = 1;
  context.globalCompositeOperation = "source-over";
  context.setLineDash([]);
  context.lineWidth = 1 / scale;
  context.strokeStyle = "#dc2626";
  context.fillStyle = "rgba(220,38,38,0.12)";
  for (const affected of preview.affected) {
    if (affected.page !== page) continue;
    context.fillRect(affected.x, affected.y, affected.width, affected.height);
    context.strokeRect(affected.x, affected.y, affected.width, affected.height);
  }
  context.fillStyle = "rgba(0,0,0,0.6)";
  for (const region of preview.regions) {
    if (region.page === page)
      context.fillRect(region.x, region.y, region.width, region.height);
  }
  context.restore();
}
