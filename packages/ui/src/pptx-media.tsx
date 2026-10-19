import type { PresentationEditor } from "@open-document/web/presentation-editor";
import { preparePresentationMedia } from "@open-document/web/pptx";
import type { EditorController, UiSnapshot } from "./controller.js";
import { messages } from "./messages.js";
import { useEffect, useRef } from "react";

export function PptxMedia({
  controller,
  state,
  editor,
  disabled,
  box,
}: {
  controller: EditorController;
  state: UiSnapshot;
  editor: PresentationEditor;
  disabled: boolean;
  box: { x: number; y: number; width: number; height: number };
}) {
  const t = messages(state.locale),
    query = editor.query;
  const events = useRef<AbortController | null>(null);
  useEffect(() => {
    const active = new AbortController();
    events.current = active;
    return () => active.abort();
  }, [editor]);
  return (
    <fieldset
      disabled={
        disabled || !!query.readOnlyReason || query.editView.kind !== "slide"
      }
    >
      <legend>{t.insertMedia}</legend>
      <label>
        {t.mediaFile}
        <input
          type="file"
          accept=".mp3,.wav,.mp4,.m4a,.webm,audio/mpeg,audio/wav,audio/mp4,audio/webm,video/mp4,video/webm"
          onChange={(event) => {
            const file = event.currentTarget.files?.[0];
            event.currentTarget.value = "";
            if (!file) return;
            const revision = editor.query.revision,
              slide = editor.query.slide,
              signal = events.current?.signal;
            controller.run(async () => {
              if (!file.size || file.size > 16777216)
                throw new Error(t.mediaInputLimit);
              const bytes = new Uint8Array(await file.arrayBuffer());
              const prepared = await preparePresentationMedia(bytes, signal);
              if (
                editor.query.revision !== revision ||
                editor.query.slide !== slide
              )
                throw new Error(t.mediaTargetChanged);
              await editor.editObjects({
                action: "insertMedia",
                bytes,
                ...prepared,
                ...box,
              });
            });
          }}
        />
      </label>
      <p>{t.mediaInsertHint}</p>
      {query.objects
        .filter((object) => object.media)
        .map((object) => (
          <p key={object.id}>
            {object.name}: {object.media!.reason || object.media!.contentType}
          </p>
        ))}
    </fieldset>
  );
}
