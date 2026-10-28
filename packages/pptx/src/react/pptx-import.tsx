import { useEffect, useRef, useState } from "react";
import type { PresentationEditor } from "../web/presentation-editor.js";
import type { PptxImportInfo } from "../web/pptx.js";
import type { EditorController, UiSnapshot } from "./context.js";
import { readFile } from "@open-document/ui/file";
import { messages } from "@open-document/ui/messages";

export function PptxImport({
  editor,
  controller,
  state,
  disabled,
}: {
  editor: PresentationEditor;
  controller: EditorController;
  state: UiSnapshot;
  disabled: boolean;
}) {
  const t = messages(state.locale),
    query = editor.query;
  const [source, setSource] = useState<{
    bytes: Uint8Array;
    slides: PptxImportInfo["slides"];
    name: string;
  } | null>(null);
  const [selected, setSelected] = useState<number[]>([]);
  const [loading, setLoading] = useState(false);
  const events = useRef<AbortController | null>(null);
  useEffect(() => () => events.current?.abort(), [editor]);
  useEffect(() => {
    setSource(null);
    setSelected([]);
    events.current?.abort();
    setLoading(false);
  }, [query.revision, query.slide, state.document?.documentId]);
  return (
    <fieldset
      disabled={
        disabled ||
        loading ||
        !!query.slideOrderReason ||
        query.editView.kind !== "slide"
      }
    >
      <legend>{t.importSlides}</legend>
      <label>
        {t.importSlidesFile}
        <input
          type="file"
          accept=".pptx,application/vnd.openxmlformats-officedocument.presentationml.presentation"
          onChange={(event) => {
            const file = event.currentTarget.files?.[0];
            event.currentTarget.value = "";
            if (!file) return;
            events.current?.abort();
            const active = new AbortController(),
              revision = editor.query.revision,
              slide = editor.query.slide;
            events.current = active;
            setSource(null);
            setLoading(true);
            controller.run(async () => {
              try {
                if (!file.size || file.size > 33554432)
                  throw new Error(t.importSlidesLimit);
                const bytes = await readFile(file, active.signal);
                const info = await editor.inspectSlides(bytes);
                active.signal.throwIfAborted();
                if (
                  editor.query.revision !== revision ||
                  editor.query.slide !== slide
                )
                  throw new Error(t.importSlidesTargetChanged);
                setSource({ bytes, slides: info.slides, name: file.name });
                setSelected(info.slides.map((slide) => slide.index));
              } catch (error) {
                if (!active.signal.aborted) throw error;
              } finally {
                if (events.current === active) setLoading(false);
              }
            });
          }}
        />
      </label>
      {source && (
        <>
          <p>{source.name}</p>
          <div role="group" aria-label={t.importSlidesSelection}>
            {source.slides.map((slide) => (
              <label key={slide.index}>
                <input
                  type="checkbox"
                  checked={selected.includes(slide.index)}
                  onChange={(event) => {
                    const checked = event.currentTarget.checked;
                    setSelected((previous) =>
                      checked
                        ? [...previous, slide.index].sort((a, b) => a - b)
                        : previous.filter((index) => index !== slide.index),
                    );
                  }}
                />
                {`${slide.index + 1}. ${slide.title || t.slide}${slide.hidden ? ` (${t.hiddenSlide})` : ""}`}
              </label>
            ))}
          </div>
          <button
            type="button"
            disabled={
              !selected.length || selected.length > 256 - query.slides.length
            }
            onClick={() =>
              controller.run(() => editor.importSlides(source.bytes, selected))
            }
          >
            {t.importSlides}
          </button>
        </>
      )}
      <p>{t.importSlidesHint}</p>
    </fieldset>
  );
}
