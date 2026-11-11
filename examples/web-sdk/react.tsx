import { StrictMode, useState } from "react";
import { createRoot } from "react-dom/client";
import {
  DocxEditor,
  type EditorOptions,
  type MountedEditor,
} from "@open-document/docx/react";
import {
  EditorColorPalette,
  EditorCommandButton,
  EditorPanel,
  EditorToolbarGroup,
} from "@open-document/ui";
import { Icon } from "@open-document/ui/icons";
import { loadDocumentAssets } from "@open-document/wasm/assets";
import { previewFonts } from "./fonts.js";
import { loadSampleDocument } from "./sample.js";

const styleNonce =
  document.querySelector<HTMLScriptElement>("#example-script")?.nonce;

function Example() {
  const [options, setOptions] = useState<EditorOptions>();
  const [editor, setEditor] = useState<MountedEditor>();
  const [attempt, setAttempt] = useState(0);
  const [mode, setMode] = useState<"edit" | "view">("edit");
  const [customToolbar, setCustomToolbar] = useState(false);
  const [formattingPanel, setFormattingPanel] = useState(false);
  const [spaciousUi, setSpaciousUi] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  function report(cause: unknown) {
    setError(cause instanceof Error ? cause.message : String(cause));
  }
  const canOpen = !loading && (!options || !!editor || !!error);
  async function open(source: File | Promise<File>) {
    setLoading(true);
    setError("");
    try {
      const file = await source;
      const document = {
        name: file.name,
        bytes: new Uint8Array(await file.arrayBuffer()),
      };
      if (editor) {
        await editor.open(document);
        return;
      }
      const [assets, fonts] = await Promise.all([
        loadDocumentAssets("docx", new URL("./", import.meta.url)),
        previewFonts([], {}),
      ]);
      setOptions({
        document,
        resources: { ...assets, ...fonts },
        ...(styleNonce ? { styleNonce } : {}),
      });
      setAttempt((value) => value + 1);
    } catch (cause) {
      report(cause);
    } finally {
      setLoading(false);
    }
  }
  async function close() {
    if (!editor) return;
    setLoading(true);
    setError("");
    try {
      if (await editor.close()) {
        setEditor(undefined);
        setOptions(undefined);
        setFormattingPanel(false);
      }
    } catch (cause) {
      report(cause);
    } finally {
      setLoading(false);
    }
  }
  return (
    <main>
      <header>
        <label>
          DOCX
          <input
            type="file"
            accept=".docx"
            disabled={!canOpen}
            onChange={(event) => {
              const file = event.currentTarget.files?.[0];
              event.currentTarget.value = "";
              if (file) void open(file);
            }}
          />
        </label>
        <button
          type="button"
          disabled={!canOpen}
          onClick={() => void open(loadSampleDocument())}
        >
          Open sample
        </button>
        <label>
          <input
            type="checkbox"
            checked={mode === "view"}
            onChange={(event) => {
              setMode(event.currentTarget.checked ? "view" : "edit");
            }}
          />
          View only
        </label>
        <label>
          <input
            type="checkbox"
            checked={customToolbar}
            onChange={(event) => {
              setCustomToolbar(event.currentTarget.checked);
              setFormattingPanel(false);
            }}
          />
          Custom toolbar
        </label>
        {editor && (
          <>
            <EditorCommandButton id="bold" commands={editor.commands}>
              Host bold
            </EditorCommandButton>
            <button
              type="button"
              disabled={loading}
              onClick={() => void close()}
            >
              Close editor
            </button>
          </>
        )}
      </header>
      {error && <p role="alert">{error}</p>}
      <div className="editor" data-spacious-ui={spaciousUi || undefined}>
        {options && (
          <DocxEditor
            key={attempt}
            {...options}
            mode={mode}
            onReady={setEditor}
            onError={report}
            {...(customToolbar
              ? {
                  slots: {
                    toolbar: ({ mode }) => (
                      <EditorToolbarGroup label="Formatting">
                        <EditorCommandButton id="bold" />
                        <EditorCommandButton id="italic" />
                        <EditorCommandButton id="undo" />
                        <button
                          type="button"
                          className="od-command"
                          aria-expanded={formattingPanel && mode === "edit"}
                          disabled={mode !== "edit"}
                          onClick={() => setFormattingPanel((open) => !open)}
                        >
                          <Icon name="format-painter" />
                          <span>Formatting panel</span>
                        </button>
                        <label>
                          <input
                            type="checkbox"
                            checked={spaciousUi}
                            onChange={(event) =>
                              setSpaciousUi(event.currentTarget.checked)
                            }
                          />
                          Spacious UI
                        </label>
                      </EditorToolbarGroup>
                    ),
                    properties: ({
                      commands,
                      focus,
                      mode,
                      portal,
                      snapshot,
                    }) => {
                      if (!editor || !formattingPanel || mode !== "edit")
                        return null;
                      const formatting =
                        editor.editor.getSnapshot().data.formatting;
                      const color = formatting?.character.color;
                      return (
                        <EditorPanel
                          label="Host formatting"
                          closeLabel="Close formatting panel"
                          close={() => {
                            setFormattingPanel(false);
                            focus();
                          }}
                        >
                          <EditorToolbarGroup label="Text color">
                            <EditorColorPalette
                              commands={commands}
                              portal={portal}
                              label="Text color"
                              custom="Custom color"
                              mixed="Mixed colors"
                              value={
                                color?.kind === "mixed"
                                  ? null
                                  : color?.kind === "value" &&
                                      color.value !== "auto"
                                    ? color.value
                                    : "000000"
                              }
                              disabled={
                                !formatting ||
                                !!formatting.fontReason ||
                                !!snapshot.busy
                              }
                              apply={(value, target) => {
                                void editor.editor.formatting
                                  .setCharacterFormat({ color: value }, () =>
                                    commands.assertTarget(target),
                                  )
                                  .catch(report);
                              }}
                            />
                          </EditorToolbarGroup>
                        </EditorPanel>
                      );
                    },
                  },
                }
              : {})}
          />
        )}
      </div>
    </main>
  );
}

const container = document.querySelector("#app");
if (!container) throw new Error("Missing example container");
createRoot(container).render(
  <StrictMode>
    <Example />
  </StrictMode>,
);
