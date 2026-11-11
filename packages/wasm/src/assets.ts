import { engineBuildIds } from "@open-document/wasm/engine-source";
import { loadEngine, type EngineSource } from "./loader.js";

export type OfficeFormat = Exclude<keyof typeof engineBuildIds, "all">;

/** Resolve the files in a same-build SDK asset directory. */
export function documentAssets(
  format: OfficeFormat,
  directory: URL,
): { engineSource: EngineSource; workerUrl: URL } {
  if (!directory.pathname.endsWith("/"))
    throw new Error("An SDK asset directory URL must end with a slash");
  return {
    engineSource: {
      url: new URL(`${format}.wasm`, directory),
      build: engineBuildIds[format],
    },
    workerUrl: new URL(`${format}-worker.js`, directory),
  };
}

export async function loadDocumentAssets(
  format: OfficeFormat,
  directory: URL,
  signal?: AbortSignal,
) {
  const { engineSource, workerUrl } = documentAssets(format, directory);
  return { engine: await loadEngine(engineSource, signal), workerUrl };
}
