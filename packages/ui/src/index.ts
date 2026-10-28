import { createElement } from "react";
import { createRoot } from "react-dom/client";
import { flushSync } from "react-dom";
import css from "../dist/styles.js";
import { EditorController } from "./controller.js";
import { EditorShell } from "./shell.js";
import type {
  EditorOptions,
  EditorHost,
  Product,
  MountedMethods,
} from "./types.js";

export type * from "./types.js";
export async function mountProduct<E extends EditorHost>(
  container: HTMLElement,
  options: EditorOptions,
  product: Product<E>,
): Promise<
  MountedMethods & {
    readonly editor: E;
    create(document: { readonly name: string }): Promise<boolean>;
  }
> {
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
  const controller = new EditorController(
    options,
    product,
    host,
    surfaces,
    () => {
      try {
        root.unmount();
      } finally {
        host.remove();
      }
    },
  );
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
    print: controller.print,
    saveAs: (name: string) => controller.saveAs(name),
    close: controller.close,
    dispose: controller.dispose,
    setTheme: (theme: "light" | "dark") => controller.setTheme(theme),
    setLocale: (locale: "en-US" | "zh-CN") => controller.setLocale(locale),
  };
  return {
    ...methods,
    create: (document) => controller.create(document),
    get editor() {
      const file = controller.getUiSnapshot().file;
      if (!file) throw new Error("Editor is unavailable");
      return file.editor;
    },
  };
}
