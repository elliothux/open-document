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
  closed: () => boolean,
): Promise<readonly EditorOutput[]> {
  const assertOpen = () => {
    if (closed()) throw new Error("Editor is disposed");
  };
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

export class PresentationOutput {
  constructor(
    private readonly generate: (
      format: "pptx" | "pdf" | "png" | "jpeg" | "images" | "jpegs",
      outputBytes?: number,
      scale?: number,
      all?: boolean,
      hidden?: boolean,
    ) => Promise<readonly EditorOutput[]>,
  ) {}
  async save(): Promise<EditorOutput> {
    return (await this.generate("pptx"))[0]!;
  }
  async exportPdf(
    all = true,
    hidden = false,
    outputBytes = 67108864,
  ): Promise<EditorOutput> {
    return (await this.generate("pdf", outputBytes, 1, all, hidden))[0]!;
  }
  async exportPng(scale = 1, outputBytes = 67108864): Promise<EditorOutput> {
    return (await this.generate("png", outputBytes, scale))[0]!;
  }
  async exportJpeg(scale = 1, outputBytes = 67108864): Promise<EditorOutput> {
    return (await this.generate("jpeg", outputBytes, scale))[0]!;
  }
  /** Exports visible slides in order at one revision, with a shared byte budget. */
  exportPageImages(
    scale = 1,
    outputBytes = 67108864,
    hidden = false,
    format: "png" | "jpeg" = "png",
  ): Promise<readonly EditorOutput[]> {
    if (format !== "png" && format !== "jpeg")
      return Promise.reject(new Error("Unsupported image output format"));
    const kind = format === "jpeg" ? "jpegs" : "images";
    return this.generate(kind, outputBytes, scale, true, hidden);
  }
}
