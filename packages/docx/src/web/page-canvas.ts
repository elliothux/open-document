import type { FoundationClient } from "./foundation.js";
import type { PageLayout } from "../core/preview.js";
import type { DocxSelectionViewRequest } from "../core/docx-hit.js";
import { CanvasSurface } from "@open-document/web-core/canvas-surface";
import {
  imageBitmapFromPixels,
  materializeImage,
} from "@open-document/web-core/image";
import type { DocxSelectionGeometry, DocxHit } from "../core/foundation.js";

/** DOCX image preparation stays with its document host. */
export class PageCanvas extends CanvasSurface {
  private comments: PageLayout["comments"] = { reason: "", items: [] };
  private commentPage = 0;
  setComments(
    comments: PageLayout["comments"],
    page: number,
    scale: number,
  ): void {
    this.comments = comments;
    this.commentPage = page;
    this.clearOverlay(scale);
  }
  override clearOverlay(scale: number): CanvasRenderingContext2D {
    const context = super.clearOverlay(scale);
    context.fillStyle = "rgba(255, 176, 0, 0.25)";
    for (const item of this.comments.items)
      for (const rect of item.rects)
        if (rect.page === this.commentPage)
          context.fillRect(rect.x, rect.y, rect.width, rect.height);
    return context;
  }
  private constructor(private readonly client: FoundationClient) {
    super(true);
  }
  async layout(
    profile: Record<string, string>,
    selectionView?: DocxSelectionViewRequest,
  ) {
    const preparation = await this.client.execute({
      operation: "layout",
      profile: profile,
      prepareImages: true,
      selectionView,
    });
    if ("missingImages" in preparation) {
      for (const key of preparation.missingImages) {
        const { bitmap, rgba } = await materializeImage(
          await this.client.execute({ operation: "imageSource", key }),
        );
        let identity: string;
        try {
          identity = await this.client.execute({
            operation: "addImage",
            key: key,
            width: bitmap.width,
            height: bitmap.height,
            rgba: rgba,
          });
        } catch (error) {
          bitmap.close();
          throw error;
        }
        this.cacheImage(identity, bitmap, rgba);
      }
    }
    const layout =
      "missingImages" in preparation
        ? await this.client.execute({
            operation: "layout",
            profile,
            selectionView,
          })
        : preparation;
    for (const identity of layout.images) {
      if (this.images.has(identity)) continue;
      const { width, height, bytes } = await this.client.execute({
        operation: "imagePixels",
        key: identity,
      });
      const bitmap = await imageBitmapFromPixels(width, height, bytes);
      this.cacheImage(identity, bitmap, bytes);
    }
    this.retainImages(new Set(layout.images));
    return layout;
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
  drawRevision(
    geometry: DocxSelectionGeometry,
    page: number,
    scale: number,
    viewport: HTMLElement,
  ): void {
    const context = this.clearOverlay(scale);
    context.fillStyle = "rgba(30, 100, 220, 0.25)";
    for (const rect of geometry.rects)
      if (rect.page === page)
        context.fillRect(rect.x, rect.y, rect.width, rect.height);
    const target = geometry.rects[0]!,
      canvas = this.canvas.getBoundingClientRect(),
      bounds = viewport.getBoundingClientRect();
    viewport.scrollBy({
      top:
        canvas.top - bounds.top + target.y * scale - viewport.clientHeight / 3,
      left:
        canvas.left - bounds.left + target.x * scale - viewport.clientWidth / 3,
    });
  }
  static async create(
    client: FoundationClient,
    signal?: AbortSignal,
  ): Promise<PageCanvas> {
    const surface = new PageCanvas(client);
    try {
      signal?.throwIfAborted();
      return surface;
    } catch (error) {
      surface.dispose();
      throw error;
    }
  }
}
