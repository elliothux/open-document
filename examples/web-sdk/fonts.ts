import type { EditorResources } from "@open-document/ui";
import { DocumentError } from "@open-document/wasm";

const defaults = [
  ["LiberationSans-Regular.ttf", "preview-sans"],
  ["LiberationSans-Bold.ttf", "preview-bold"],
  ["LiberationSans-Italic.ttf", "preview-italic"],
  ["LiberationSans-BoldItalic.ttf", "preview-bold-italic"],
  ["NotoSansSC-Regular.ttf", "preview-cjk"],
  ["DejaVuMathTeXGyre.ttf", "preview-math"],
] as const;

export async function previewFonts(
  files: Iterable<File>,
  overrides: Readonly<Record<string, string>>,
): Promise<Pick<EditorResources, "fonts" | "profile">> {
  const fonts: { identity: string; bytes: Uint8Array }[] = await Promise.all(
    defaults.map(async ([file, identity]) => {
      const url = new URL(`./fonts/${file}`, import.meta.url);
      try {
        const response = await fetch(url, { cache: "no-store" });
        if (!response.ok) throw new Error(`HTTP ${response.status}`);
        return {
          identity,
          bytes: new Uint8Array(await response.arrayBuffer()),
        };
      } catch (cause) {
        throw new DocumentError(
          "font-load",
          `Cannot load preview font ${file}: ${cause instanceof Error ? cause.message : String(cause)}`,
          "",
          -1,
          "font",
          { cause, resource: url.href },
        );
      }
    }),
  );
  for (const file of files)
    fonts.push({
      identity: file.name.replace(/\.[^.]*$/, ""),
      bytes: new Uint8Array(await file.arrayBuffer()),
    });
  // shortcut: one regular CJK face; add style faces when CJK style fidelity is required.
  return {
    fonts,
    profile: {
      "*": "preview-sans",
      "*|bold": "preview-bold",
      "*|italic": "preview-italic",
      "*|bold|italic": "preview-bold-italic",
      "Liberation Sans": "preview-sans",
      "Liberation Sans|bold": "preview-bold",
      "Liberation Sans|italic": "preview-italic",
      "Liberation Sans|bold|italic": "preview-bold-italic",
      "Noto Sans SC": "preview-cjk",
      "Cambria Math": "preview-math",
      "Cambria Math|bold": "preview-math",
      "Cambria Math|italic": "preview-math",
      "Cambria Math|bold|italic": "preview-math",
      ...overrides,
    },
  };
}
