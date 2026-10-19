import type { FoundationClient } from "./foundation.js";
import { decodeImage } from "./image.js";

/** Decode incoming resources before the core commits the table and media transaction. */
export async function prepareDocxFragmentImages(
  client: FoundationClient,
  revision: number,
  fragment: string,
): Promise<void> {
  const resources = await client.tableFragmentImages(revision, fragment);
  for (const image of resources.images) {
    const { bitmap, rgba } = await decodeImage(image.bytes);
    try {
      await client.addImage(image.key, bitmap.width, bitmap.height, rgba);
    } finally {
      bitmap.close();
    }
  }
}
