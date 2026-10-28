import type { FoundationClient } from "./foundation.js";
import { decodeImage } from "@open-document/web-core/image";
import type { DocxFragmentImages } from "../core/foundation.js";

/** Decode incoming resources before the core commits the table and media transaction. */
export async function prepareDocxFragmentImages(
  client: Pick<
    FoundationClient,
    "tableFragmentImages" | "bodyFragmentImages" | "addImage"
  >,
  revision: number,
  fragment: string,
  kind: "body" | "cells" = "cells",
): Promise<void> {
  const resources =
    kind === "body"
      ? await client.bodyFragmentImages(revision, fragment)
      : await client.tableFragmentImages(revision, fragment);
  await prepareDocxImages(client, resources);
}

/** Decode only core-validated local resources and release every platform bitmap. */
export async function prepareDocxImages(
  client: Pick<FoundationClient, "addImage">,
  resources: DocxFragmentImages,
): Promise<void> {
  for (const image of resources.images) {
    const { bitmap, rgba } = await decodeImage(image.bytes);
    try {
      await client.addImage(image.key, bitmap.width, bitmap.height, rgba);
    } finally {
      bitmap.close();
    }
  }
}
