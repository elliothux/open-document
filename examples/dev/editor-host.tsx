import { useEffect, useRef } from "react";
import {
  mountEditor,
  type EditorOptions,
  type MountedEditor,
} from "@open-document/ui";
import "../../packages/ui/src/styles/ui.css?inline";

// Keep the mounted session while React refreshes the SDK's UI components.
if (import.meta.hot) {
  import.meta.hot.accept("@open-document/ui", () => {});
  import.meta.hot.accept(
    "../../packages/ui/src/styles/ui.css?inline",
    (module) => {
      const css: unknown = module?.default;
      if (typeof css !== "string") return;
      for (const host of document.querySelectorAll(".open-document-editor")) {
        const style = host.shadowRoot?.querySelector("style");
        if (style) style.textContent = css;
      }
    },
  );
}

export function EditorHost({
  options,
  onReady,
  onError,
}: {
  options: EditorOptions;
  onReady: (editor: MountedEditor | undefined) => void;
  onError: (error: string) => void;
}) {
  const container = useRef<HTMLDivElement>(null);
  useEffect(() => {
    if (!container.current) return;
    const abort = new AbortController();
    let mounted: MountedEditor | undefined;
    const element = container.current;
    void Promise.resolve()
      .then(() => {
        abort.signal.throwIfAborted();
        return mountEditor(element, { ...options, signal: abort.signal });
      })
      .then(async (editor) => {
        if (abort.signal.aborted) {
          await editor.dispose();
          return;
        }
        mounted = editor;
        onReady(editor);
      })
      .catch((error) => {
        if (!abort.signal.aborted) onError(String(error));
      });
    return () => {
      abort.abort();
      onReady(undefined);
      void mounted?.dispose().catch((error) => onError(String(error)));
    };
  }, [options, onReady, onError]);
  return <div id="editor" ref={container} />;
}
