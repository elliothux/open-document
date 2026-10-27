const defaults = [
  ["LiberationSans-Regular.ttf", "preview-sans"],
  ["LiberationSans-Bold.ttf", "preview-bold"],
  ["LiberationSans-Italic.ttf", "preview-italic"],
  ["LiberationSans-BoldItalic.ttf", "preview-bold-italic"],
  ["NotoSansSC-Regular.ttf", "preview-cjk"],
  ["DejaVuMathTeXGyre.ttf", "preview-math"],
];

export async function previewFonts(files, overrides) {
  const fonts = await Promise.all(
    defaults.map(async ([file, identity]) => {
      const response = await fetch(
        new URL(`./fonts/${file}`, import.meta.url),
        { cache: "no-store" },
      );
      if (!response.ok)
        throw new Error(
          `Cannot load preview font: ${file} (${response.status})`,
        );
      return { identity, bytes: new Uint8Array(await response.arrayBuffer()) };
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
      "Cambria Math": "preview-math",
      "Cambria Math|bold": "preview-math",
      "Cambria Math|italic": "preview-math",
      "Cambria Math|bold|italic": "preview-math",
      ...overrides,
    },
  };
}
