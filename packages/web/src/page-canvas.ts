import type { FoundationClient } from "./foundation.js";
import { CanvasSurface } from "./canvas-surface.js";
import { decodeImage } from "./image.js";
import type {
  DocxSelectionGeometry,
  DocxHit,
} from "@open-document/wasm/foundation";

/** DOCX image preparation stays with its document host. */
export class PageCanvas extends CanvasSurface {
  private readonly keys = new Map<string, string>();
  private constructor(private readonly client: FoundationClient) {
    super();
  }
  async layout(profile: Record<string, string>) {
    await this.prepare();
    return this.client.layout(profile);
  }
  private async prepare(signal?: AbortSignal): Promise<void> {
    signal?.throwIfAborted();
    const flow = await this.client.flow();
    const paragraphs = [
      ...flow.paragraphs,
      ...flow.headers.flat(),
      ...flow.tables.flatMap((table) => table.rows.flat(2)),
    ];
    const keys = new Set(
      paragraphs.flatMap((paragraph) =>
        paragraph.spans.flatMap((span) => (span.image ? [span.image.key] : [])),
      ),
    );
    for (const key of this.keys.keys())
      if (!keys.has(key)) this.keys.delete(key);
    const retained = new Set(this.keys.values());
    for (const [identity, bitmap] of this.images)
      if (!retained.has(identity)) {
        bitmap.close();
        this.images.delete(identity);
      }
    for (const key of keys) {
      if (this.keys.has(key)) continue;
      const { bitmap, rgba } = await decodeImage(
        await this.client.imageBytes(key),
        signal,
      );
      try {
        const identity = await this.client.addImage(
          key,
          bitmap.width,
          bitmap.height,
          rgba,
        );
        if (this.images.has(identity)) bitmap.close();
        else this.images.set(identity, bitmap);
        this.keys.set(key, identity);
      } catch (error) {
        bitmap.close();
        throw error;
      }
    }
    signal?.throwIfAborted();
  }
  drawSelection(
    page: number,
    scale: number,
    geometry: DocxSelectionGeometry | undefined,
    caret: DocxHit | undefined,
  ): void {
    const context = this.clearOverlay(scale);
    context.fillStyle = "rgba(30, 100, 220, 0.25)";
    for (const rect of geometry?.rects ?? []) {
      if (rect.page === page)
        context.fillRect(rect.x, rect.y, rect.width, rect.height);
    }
    if (caret) {
      context.fillStyle = "#174ca0";
      context.fillRect(caret.x, caret.y, 1 / scale, caret.height);
    }
  }
  static async create(
    client: FoundationClient,
    signal?: AbortSignal,
  ): Promise<PageCanvas> {
    const surface = new PageCanvas(client);
    try {
      await surface.prepare(signal);
      return surface;
    } catch (error) {
      surface.dispose();
      throw error;
    }
  }
  override dispose(): void {
    this.keys.clear();
    super.dispose();
  }
}
