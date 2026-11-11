import type { FoundationClient } from "./foundation.js";
import { materializeImage } from "@open-document/web-core/image";
import type { DocxFragmentImages } from "../core/foundation.js";

/** Decode incoming resources before the core commits the table and media transaction. */
export async function prepareDocxFragmentImages(
  client: Pick<FoundationClient, "execute">,
  revision: number,
  fragment: string,
  kind: "body" | "cells" = "cells",
): Promise<void> {
  const resources = await client.execute({
    operation: kind === "body" ? "bodyFragmentImages" : "tableFragmentImages",
    revision,
    fragment,
    preparePixels: true,
  });
  await prepareDocxImages(client, resources);
}

/** Decode only core-validated local resources and release every platform bitmap. */
export async function prepareDocxImages(
  client: Pick<FoundationClient, "execute">,
  resources: DocxFragmentImages,
): Promise<void> {
  for (const image of resources.images) {
    if (image.rgba) {
      await client.execute({
        operation: "addImage",
        key: image.key,
        width: image.width,
        height: image.height,
        rgba: image.bytes,
      });
      continue;
    }
    const { bitmap, rgba } = await materializeImage({
      kind: "encoded",
      bytes: image.bytes,
      header: image,
    });
    try {
      await client.execute({
        operation: "addImage",
        key: image.key,
        width: bitmap.width,
        height: bitmap.height,
        rgba,
      });
    } finally {
      bitmap.close();
    }
  }
}
