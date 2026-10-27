import type { EditorResources } from "@open-document/ui";
import wasmUrl from "@open-document/wasm/engine.wasm?url";
import workerUrl from "@open-document/web/worker?worker&url";
import { previewFonts } from "../web-sdk/fonts.js";

export async function previewResources(): Promise<EditorResources> {
  const response = await fetch(wasmUrl, { cache: "no-store" });
  if (!response.ok)
    throw new Error("Build engine.wasm with bun run build before previewing");
  return {
    wasm: await response.arrayBuffer(),
    workerUrl: new URL(workerUrl, location.href),
    ...(await previewFonts([], {})),
  };
}
