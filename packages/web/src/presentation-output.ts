import type { PptxQuery, PptxLayout } from "@open-document/wasm/pptx";
import type { EditorOutput, EditorState } from "./editor-state.js";
import type { PptxClient } from "./pptx.js";
import type { PresentationCanvas } from "./presentation-canvas.js";

export async function presentationOutputs(
  client: PptxClient,
  surface: PresentationCanvas,
  state: PptxQuery,
  layout: PptxLayout | undefined,
  profile: Record<string, string>,
  format: "pptx" | "pdf" | "png" | "jpeg" | "images" | "jpegs",
  all: boolean,
  hidden: boolean,
  outputBytes: number,
  scale: number,
  observable: EditorState<PptxQuery>,
  assertOpen: () => void,
): Promise<readonly EditorOutput[]> {
  const revision = state.revision;
  let buffers: Uint8Array[];
  const collection = format === "images" || format === "jpegs";
  const imageFormat = format === "jpeg" || format === "jpegs" ? "jpeg" : "png";
  if (collection)
    buffers = await surface.exportPageImages(
      client,
      revision,
      profile,
      scale,
      outputBytes,
      hidden,
      assertOpen,
      imageFormat,
    );
  else if (format === "png" || format === "jpeg") {
    if (!layout) throw new Error("Slide layout is unavailable");
    buffers = [
      await surface.exportSlideImage(layout, state, scale, outputBytes, format),
    ];
  } else if (format === "pdf")
    buffers = [
      await surface.exportPdf(
        client,
        revision,
        profile,
        all,
        hidden,
        outputBytes,
      ),
    ];
  else buffers = [await client.execute({ operation: "savePptx", revision })];
  if (collection) assertOpen();
  return Object.freeze(
    buffers.map((bytes) =>
      observable.output(revision, collection ? imageFormat : format, bytes),
    ),
  );
}
