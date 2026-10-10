import { Connection } from "./connection";
import {
  docxFlow,
  pageLayout,
  type DocxFlow,
  type PageLayout,
} from "@open-document/wasm/preview";
import {
  docxQuery,
  shapeBatch,
  resourceBudget,
  type Budget,
  type DocxQuery,
  type ShapeBatch,
} from "@open-document/wasm/foundation";

/** Text shaping, bounded DOCX operations and preview/PDF, owned by one Worker. */
export class FoundationClient {
  private constructor(private readonly connection: Connection) {}

  static async open(
    wasm: ArrayBuffer,
    workerUrl: URL,
  ): Promise<FoundationClient> {
    const client = new FoundationClient(
      new Connection(new Worker(workerUrl, { type: "module" })),
    );
    try {
      await client.connection.request({ operation: "openFoundation", wasm });
      return client;
    } catch (error) {
      client.dispose();
      throw error;
    }
  }
  async addFont(bytes: Uint8Array, identity: string): Promise<void> {
    await this.connection.request({ operation: "font", bytes, identity });
  }
  async defaultBudget(): Promise<Budget> {
    return resourceBudget(
      await this.connection.request({ operation: "budget" }),
    );
  }
  async shape(text: string, size = 32, language = "und"): Promise<ShapeBatch> {
    return shapeBatch(
      await this.connection.request({
        operation: "shape",
        text,
        size,
        language,
      }),
    );
  }
  async openDocx(bytes: Uint8Array, budget: Budget): Promise<DocxQuery> {
    return docxQuery(
      await this.connection.request({ operation: "openDocx", bytes, budget }),
    );
  }
  async query(): Promise<DocxQuery> {
    return docxQuery(await this.connection.request({ operation: "query" }));
  }
  async replaceNode(
    node: number,
    revision: number,
    text: string,
  ): Promise<number> {
    const result = await this.connection.request({
      operation: "replaceNode",
      node,
      revision,
      text,
    });
    if (typeof result !== "number")
      throw new Error("Invalid revision response");
    return result;
  }
  async saveDocx(): Promise<Uint8Array> {
    const result = await this.connection.request({ operation: "saveDocx" });
    if (!(result instanceof Uint8Array))
      throw new Error("Invalid byte response");
    return result;
  }
  async flow(): Promise<DocxFlow> {
    return docxFlow(await this.connection.request({ operation: "flow" }));
  }
  async layout(profile: Record<string, string>): Promise<PageLayout> {
    return pageLayout(
      await this.connection.request({ operation: "layout", profile }),
    );
  }
  async exportPdf(outputBytes: number, layoutId?: number): Promise<Uint8Array> {
    const result = await this.connection.request({
      operation: "exportPdf",
      outputBytes,
      layoutId,
    });
    if (!(result instanceof Uint8Array)) throw new Error("Invalid PDF bytes");
    return result;
  }
  async imageBytes(key: string): Promise<Uint8Array> {
    const result = await this.connection.request({
      operation: "imageBytes",
      key,
    });
    if (!(result instanceof Uint8Array)) throw new Error("Invalid image bytes");
    return result;
  }
  async addImage(
    key: string,
    width: number,
    height: number,
    bytes: Uint8Array,
  ): Promise<void> {
    await this.connection.request({
      operation: "image",
      key,
      width,
      height,
      bytes,
    });
  }
  dispose(): void {
    this.connection.dispose();
  }
}

/** One renderer per probe; cached paths share that probe's lifetime. */
export class OutlineCanvas {
  private readonly paths = new Map<string, Path2D>();
  private closed = false;
  drawPage(
    context: CanvasRenderingContext2D,
    layout: PageLayout,
    index: number,
    images: ReadonlyMap<string, ImageBitmap> = new Map(),
  ): void {
    if (this.closed) throw new Error("Renderer is disposed");
    const page = layout.pages[index];
    if (!page) throw new Error("Unknown page");
    for (const outline of layout.outlines)
      if (!this.paths.has(outline.key))
        this.paths.set(outline.key, new Path2D(outline.path));
    context.save();
    try {
      context.beginPath();
      context.rect(0, 0, page.width, page.height);
      context.clip();
      context.fillStyle = "white";
      context.fillRect(0, 0, page.width, page.height);
      context.strokeStyle = "black";
      context.lineWidth = 0.5;
      for (const fill of page.fills) {
        context.fillStyle = `#${fill.color}`;
        context.fillRect(fill.x, fill.y, fill.width, fill.height);
      }
      for (const border of page.borders)
        context.strokeRect(border.x, border.y, border.width, border.height);
      for (const line of page.lines) {
        for (const image of line.images) {
          const bitmap = images.get(image.key);
          if (!bitmap) throw new Error(`Missing image: ${image.key}`);
          context.drawImage(
            bitmap,
            image.x,
            image.y,
            image.width,
            image.height,
          );
        }
        for (const run of line.runs) {
          context.fillStyle = `#${run.color}`;
          this.drawGlyphs(context, run.glyphs, run.x, run.baseline);
        }
      }
    } finally {
      context.restore();
    }
  }
  draw(
    context: CanvasRenderingContext2D,
    batch: ShapeBatch,
    x = 0,
    baseline = 48,
  ): void {
    if (this.closed) throw new Error("Renderer is disposed");
    for (const outline of batch.outlines)
      this.paths.set(outline.key, new Path2D(outline.path));
    this.drawGlyphs(context, batch.glyphs, x, baseline);
  }
  private drawGlyphs(
    context: CanvasRenderingContext2D,
    glyphs: ShapeBatch["glyphs"],
    x: number,
    baseline: number,
  ): void {
    for (const glyph of glyphs) {
      const path = this.paths.get(glyph.outline);
      if (!path) throw new Error(`Missing outline: ${glyph.outline}`);
      context.save();
      context.translate(x + glyph.x, baseline + glyph.y);
      context.scale(glyph.scale, -glyph.scale);
      context.fill(path);
      context.restore();
    }
  }
  dispose(): void {
    this.paths.clear();
    this.closed = true;
  }
}
