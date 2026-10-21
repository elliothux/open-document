import { CanvasSurface } from "./canvas-surface.js";
import { decodeImage } from "./image.js";
import type { XlsxClient } from "./xlsx.js";

/** Keeps decoded worksheet resources with the existing Canvas surface. */
export class SpreadsheetCanvas extends CanvasSurface {
  private readonly keys = new Map<string, string>();

  private async add(
    client: XlsxClient,
    revision: number,
    key: string,
    bytes: Uint8Array,
    signal?: AbortSignal,
  ): Promise<void> {
    const { bitmap, rgba } = await decodeImage(bytes, signal);
    try {
      const identity = await client.addImage(
        revision,
        key,
        bitmap.width,
        bitmap.height,
        rgba,
      );
      signal?.throwIfAborted();
      if (this.images.has(identity)) bitmap.close();
      else this.images.set(identity, bitmap);
      this.keys.set(key, identity);
    } catch (error) {
      bitmap.close();
      throw error;
    }
  }

  async addPicture(
    client: XlsxClient,
    revision: number,
    bytes: Uint8Array,
    signal?: AbortSignal,
  ): Promise<void> {
    const resource = await client.pictureResource(revision, bytes);
    await this.add(client, revision, resource.key, bytes, signal);
  }

  async prepare(
    client: XlsxClient,
    revision: number,
    sheets: string[],
    profile: Record<string, string>,
    signal?: AbortSignal,
  ): Promise<void> {
    signal?.throwIfAborted();
    const keys = new Set<string>();
    for (const sheet of sheets) {
      const pictures = await client.pictures(revision, sheet, profile);
      for (const item of pictures.items) keys.add(item.key);
    }
    for (const key of this.keys.keys())
      if (!keys.has(key)) this.keys.delete(key);
    const retained = new Set(this.keys.values());
    for (const [identity, bitmap] of this.images) {
      if (!retained.has(identity)) {
        bitmap.close();
        this.images.delete(identity);
      }
    }
    for (const key of keys) {
      if (!this.keys.has(key))
        await this.add(
          client,
          revision,
          key,
          await client.imageBytes(revision, key),
          signal,
        );
    }
    signal?.throwIfAborted();
  }

  override dispose(): void {
    this.keys.clear();
    super.dispose();
  }
}
