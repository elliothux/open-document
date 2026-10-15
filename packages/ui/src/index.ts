import { createElement } from "react";
import { createRoot } from "react-dom/client";
import { flushSync } from "react-dom";
import css from "../dist/styles.css" with { type: "text" };
import { EditorController } from "./controller.js";
import { EditorShell } from "./shell.js";
import type { EditorOptions, MountedEditor } from "./types.js";

export type {
  EditorDocument,
  OfficeDocument,
  EditorOptions,
  EditorResources,
  Locale,
  MountedEditor,
  MountedSnapshot,
  SavedDocument,
  Theme,
} from "./types.js";

/** Append one editor without replacing the caller's DOM or ShadowRoot. */
export async function mountEditor(
  container: HTMLElement,
  options: EditorOptions,
): Promise<MountedEditor> {
  options.signal?.throwIfAborted();
  const document = container.ownerDocument;
  const host = document.createElement("div");
  host.className = "open-document-editor";
  const shadow = host.attachShadow({ mode: "open" });
  const style = document.createElement("style");
  if (options.styleNonce) style.nonce = options.styleNonce;
  style.textContent = css;
  const reactContainer = document.createElement("div");
  reactContainer.style.height = "100%";
  const portal = document.createElement("div");
  portal.dataset.odPortal = "";
  const surfaces = document.createElement("div");
  surfaces.className = "od-surfaces";
  shadow.append(style, reactContainer, portal);
  container.append(host);
  const root = createRoot(reactContainer);
  const controller = new EditorController(options, host, surfaces, () => {
    try {
      root.unmount();
    } finally {
      host.remove();
    }
  });
  try {
    flushSync(() =>
      root.render(createElement(EditorShell, { controller, portal })),
    );
    await controller.initialize();
  } catch (error) {
    try {
      await controller.dispose();
    } catch (cleanup) {
      throw new AggregateError([error, cleanup], "Mount and cleanup failed");
    }
    throw error;
  }
  const methods = {
    getSnapshot: controller.getSnapshot,
    subscribe: controller.subscribe,
    open: controller.open,
    save: controller.save,
    saveAs: (name: string) => controller.saveAs(name),
    close: controller.close,
    dispose: controller.dispose,
    setTheme: (theme: "light" | "dark") => controller.setTheme(theme),
    setLocale: (locale: "en-US" | "zh-CN") => controller.setLocale(locale),
  };
  switch (options.format) {
    case "docx":
      return {
        ...methods,
        format: "docx",
        create: (document: { readonly name: string }) =>
          controller.create(document),
        get editor() {
          const file = controller.getUiSnapshot().file;
          if (file?.format !== "docx")
            throw new Error("DOCX editor is unavailable");
          return file.editor;
        },
      };
    case "xlsx":
      return {
        ...methods,
        create: (document: { readonly name: string }) =>
          controller.create(document),
        format: "xlsx",
        get editor() {
          const file = controller.getUiSnapshot().file;
          if (file?.format !== "xlsx")
            throw new Error("XLSX editor is unavailable");
          return file.editor;
        },
      };
    case "pptx":
      return {
        ...methods,
        create: (document: { readonly name: string }) =>
          controller.create(document),
        format: "pptx",
        get editor() {
          const file = controller.getUiSnapshot().file;
          if (file?.format !== "pptx")
            throw new Error("PPTX editor is unavailable");
          return file.editor;
        },
      };
    case "pdf":
      return {
        ...methods,
        format: "pdf",
        get editor() {
          const file = controller.getUiSnapshot().file;
          if (file?.format !== "pdf")
            throw new Error("PDF editor is unavailable");
          return file.editor;
        },
      };
  }
}
