import { CanvasSurface } from "@open-document/web-core/canvas-surface";
import { materializeImage } from "@open-document/web-core/image";
import type { ImagePreparation } from "@open-document/wasm/abi/drawing";
import type { XlsxClient } from "./xlsx.js";

/** Keeps decoded worksheet resources with the existing Canvas surface. */
export class SpreadsheetCanvas extends CanvasSurface {
  constructor(private readonly mode: "screen" | "print" = "screen") {
    super();
  }

  private async add(
    client: XlsxClient,
    revision: number,
    key: string,
    image: ImagePreparation,
    signal?: AbortSignal,
    registerPixels = false,
  ): Promise<void> {
    const { bitmap, rgba } = await materializeImage(image, signal);
    let identity: string;
    try {
      identity =
        image.kind === "rgba" && !registerPixels
          ? image.key
          : await client.execute({
              operation: "imageXlsx",
              revision,
              key,
              width: bitmap.width,
              height: bitmap.height,
              bytes: rgba,
            });
      signal?.throwIfAborted();
    } catch (error) {
      bitmap.close();
      throw error;
    }
    this.cacheImage(identity, bitmap, this.mode === "print" ? rgba : undefined);
    this.imageKeys.set(key, identity);
  }

  async addPicture(
    client: XlsxClient,
    revision: number,
    bytes: Uint8Array,
    signal?: AbortSignal,
  ): Promise<void> {
    const resource = await client.execute({
      operation: "pictureResourceXlsx",
      revision,
      bytes,
      preparePixels: true,
    });
    await this.add(
      client,
      revision,
      resource.key,
      resource.bytes
        ? {
            kind: "rgba",
            key: resource.key,
            width: resource.width,
            height: resource.height,
            bytes: resource.bytes,
          }
        : { kind: "encoded", bytes, header: resource },
      signal,
      true,
    );
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
      const pictures = await client.execute({
        operation: "picturesXlsx",
        revision: revision,
        sheet: sheet,
        profile: profile,
      });
      for (const item of pictures.items) keys.add(item.key);
    }
    this.retainImageKeys(keys);
    for (const key of keys) {
      if (!this.imageKeys.has(key))
        await this.add(
          client,
          revision,
          key,
          await client.execute({
            operation: "prepareImageXlsx",
            revision: revision,
            key: key,
          }),
          signal,
        );
    }
    signal?.throwIfAborted();
  }
}
