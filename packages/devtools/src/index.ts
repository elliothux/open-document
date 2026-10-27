import { createElement } from "react";
import { createRoot } from "react-dom/client";
import { DevToolsPanel, type DevToolsSource } from "./panel.js";

export type { DevToolsSource } from "./panel.js";

/** Inject a separate inspector; the caller owns its development-only setup and disposal. */
export function setupDevTools(source: DevToolsSource): () => void {
  const host = document.createElement("aside");
  host.dataset.openDocumentDevtools = "";
  const shadow = host.attachShadow({ mode: "open" });
  const style = document.createElement("style");
  style.textContent =
    ":host{position:fixed;right:12px;bottom:12px;z-index:100000;width:360px;max-width:90vw;max-height:40vh;overflow:auto;background:#18202b;color:#e4e9f0;border:1px solid #526074;border-radius:6px;font:12px/1.4 monospace}summary{padding:8px;cursor:pointer}pre{padding:8px;margin:0;white-space:pre-wrap;overflow-wrap:anywhere}";
  const container = document.createElement("div");
  shadow.append(style, container);
  document.body.append(host);
  const root = createRoot(container);
  root.render(createElement(DevToolsPanel, { source }));
  let disposed = false;
  return () => {
    if (disposed) return;
    disposed = true;
    queueMicrotask(() => {
      root.unmount();
      host.remove();
    });
  };
}
