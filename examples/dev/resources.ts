import type { EditorResources } from "@open-document/ui/types";
import type { EditorFormat } from "@open-document/web-core/editor-state";
import { loadEngine } from "@open-document/wasm";
import { engineBuildId } from "@open-document/wasm/engine-source";
import wasmUrl from "@open-document/wasm/engine.wasm?url";
import { previewFonts } from "../web-sdk/fonts.js";

export async function previewResources(
  format: EditorFormat,
): Promise<EditorResources> {
  const engine = await loadEngine({
    url: new URL(wasmUrl, location.href),
    build: engineBuildId,
  });
  const worker =
    format === "docx"
      ? await import("@open-document/docx/worker?worker&url")
      : format === "xlsx"
        ? await import("@open-document/xlsx/worker?worker&url")
        : format === "pptx"
          ? await import("@open-document/pptx/worker?worker&url")
          : await import("@open-document/pdf/worker?worker&url");
  return {
    engine,
    workerUrl: new URL(worker.default, location.href),
    ...(await previewFonts([], {})),
  };
}
