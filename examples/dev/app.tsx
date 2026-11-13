import { useEffect, useRef, useState } from "react";
import type { EditorOptions, MountedEditor } from "./formats.js";
import { EditorHost } from "./editor-host.js";
import { previewResources } from "./resources.js";
import {
  AccentIcon,
  type AccentIconName,
} from "@open-document/ui/accent-icons";

const formats: readonly (readonly [string, AccentIconName])[] = [
  ["docx", "file-text"],
  ["xlsx", "file-spreadsheet"],
  ["pptx", "presentation"],
  ["pdf", "file"],
];

export function App() {
  const input = useRef<HTMLInputElement>(null);
  const [options, setOptions] = useState<EditorOptions>();
  const [editor, setEditor] = useState<MountedEditor>();
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);
  const [dragging, setDragging] = useState(false);

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
        extension === "csv" || extension === "tsv" ? 4194304 : 33554432;
      if (format !== "pptx" && format !== "pdf" && file.size > inputLimit)
        throw new Error("Document input exceeds budget");
      const source =
        format === "pptx" || format === "pdf"
          ? ({ format, document: file } as const)
          : ({
              format,
              document: {
                name: file.name,
                bytes: new Uint8Array(await file.arrayBuffer()),
              },
            } as const);
      if (editor?.format === format) {
        await editor.open(source.document);
        return;
      }
      const resources = await previewResources(format);
      if (editor && !(await editor.close())) return;
      setOptions({
        ...source,
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
        <div
          className="empty"
          data-dragging={dragging || undefined}
          onDragOver={(event) => {
            event.preventDefault();
            setDragging(true);
          }}
          onDragLeave={() => setDragging(false)}
          onDrop={(event) => {
            event.preventDefault();
            setDragging(false);
            const file = event.dataTransfer.files[0];
            if (file) void open(file);
          }}
        >
          <section className="empty-card">
            <div className="empty-mark" aria-hidden="true">
              {dragging ? (
                <span data-kind="upload">
                  <AccentIcon name="cloud-upload" />
                </span>
              ) : (
                formats.map(([kind, icon]) => (
                  <span key={kind} data-kind={kind}>
                    <AccentIcon name={icon} />
                  </span>
                ))
              )}
            </div>
            <h1>Open Document</h1>
            <p>拖入文件，或从本地选择一个文档开始编辑。</p>
            <button type="button" disabled={opening} onClick={chooseFile}>
              {opening ? "正在打开…" : "打开文件"}
            </button>
            <ul aria-label="支持的格式" translate="no" className="notranslate">
              {["DOCX", "XLSX", "CSV", "PPTX", "PDF"].map((format) => (
                <li key={format}>{format}</li>
              ))}
            </ul>
          </section>
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
