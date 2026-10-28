import { useEffect, useRef, useState } from "react";
import type { EditorOptions, MountedEditor } from "./formats.js";
import { EditorHost } from "./editor-host.js";
import { previewResources } from "./resources.js";

export function App() {
  const input = useRef<HTMLInputElement>(null);
  const [options, setOptions] = useState<EditorOptions>();
  const [editor, setEditor] = useState<MountedEditor>();
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    if (!editor) return;
    return editor.subscribe(() => {
      if (editor.getSnapshot().closed) {
        setOptions(undefined);
        setEditor(undefined);
      }
    });
  }, [editor]);

  useEffect(() => {
    if (!editor || !import.meta.env.DEV) return;
    const abort = new AbortController();
    void import("@open-document/devtools")
      .then(({ setupDevTools }) => {
        if (abort.signal.aborted) return;
        const dispose = setupDevTools(editor);
        abort.signal.addEventListener("abort", dispose, { once: true });
      })
      .catch((error) => {
        if (!abort.signal.aborted) setError(String(error));
      });
    return () => abort.abort();
  }, [editor]);

  function chooseFile() {
    input.current?.click();
  }

  async function open(file: File) {
    if (loading) return;
    setLoading(true);
    setError("");
    try {
      const extension = file.name.split(".").at(-1)?.toLowerCase();
      const format =
        extension === "csv" || extension === "tsv" ? "xlsx" : extension;
      if (
        format !== "docx" &&
        format !== "xlsx" &&
        format !== "pptx" &&
        format !== "pdf"
      )
        throw new Error("请选择 DOCX、XLSX、CSV、TSV、PPTX 或 PDF");
      const inputLimit =
        format === "pdf"
          ? 67108864
          : extension === "csv" || extension === "tsv"
            ? 4194304
            : 33554432;
      if (file.size > inputLimit)
        throw new Error("Document input exceeds budget");
      const document = {
        name: file.name,
        bytes: new Uint8Array(await file.arrayBuffer()),
      };
      if (editor?.format === format) {
        await editor.open(document);
        return;
      }
      const resources = await previewResources(format);
      if (editor && !(await editor.close())) return;
      setOptions({
        format,
        document,
        resources,
        locale: "zh-CN",
        onOpen: chooseFile,
      });
    } catch (error) {
      setError(String(error));
    } finally {
      setLoading(false);
    }
  }

  const opening = loading || (!!options && !editor && !error);
  return (
    <main>
      <input
        ref={input}
        id="document"
        type="file"
        hidden
        accept=".docx,.xlsx,.csv,.tsv,.pptx,.pdf"
        onChange={(event) => {
          const file = event.currentTarget.files?.[0];
          event.currentTarget.value = "";
          if (file) void open(file);
        }}
      />
      {options && (
        <EditorHost options={options} onReady={setEditor} onError={setError} />
      )}
      {!editor && (
        <div className="empty">
          <button type="button" disabled={opening} onClick={chooseFile}>
            {opening ? "正在打开…" : "打开文件"}
          </button>
        </div>
      )}
      {error && (
        <p className="error" role="alert">
          {error}
        </p>
      )}
    </main>
  );
}
