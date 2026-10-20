import type { PresentationEditor } from "@open-document/web/presentation-editor";
import { preparePresentationMedia } from "@open-document/web/pptx";
import type { EditorController, UiSnapshot } from "./controller.js";
import { messages } from "./messages.js";
import { useEffect, useRef, useState } from "react";
import type { PptxMediaPlayback } from "@open-document/web/pptx";

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
      {query.mediaPlayback.value && (
        <MediaPlayback
          key={
            query.selection.object + JSON.stringify(query.mediaPlayback.value)
          }
          value={query.mediaPlayback.value}
          controller={controller}
          editor={editor}
          state={state}
        />
      )}
      {query.objects.find((object) => object.id === query.selection.object)
        ?.media &&
        query.mediaPlayback.reason && <p>{query.mediaPlayback.reason}</p>}
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

function MediaPlayback({
  value,
  controller,
  editor,
  state,
}: {
  value: PptxMediaPlayback;
  controller: EditorController;
  editor: PresentationEditor;
  state: UiSnapshot;
}) {
  const [draft, setDraft] = useState(value),
    t = messages(state.locale);
  return (
    <form
      onSubmit={(event) => {
        event.preventDefault();
        controller.run(() =>
          editor.editObjects({ action: "mediaPlayback", value: draft }),
        );
      }}
    >
      <label>
        <input
          type="checkbox"
          checked={draft.loop}
          onChange={(event) =>
            setDraft({ ...draft, loop: event.currentTarget.checked })
          }
        />
        {t.mediaLoop}
      </label>
      <label>
        {t.mediaVolume}
        <input
          type="number"
          required
          min={0}
          max={100}
          step={0.001}
          value={draft.volume / 1000}
          onChange={(event) =>
            setDraft({
              ...draft,
              volume: Math.round(event.currentTarget.valueAsNumber * 1000),
            })
          }
        />
      </label>
      <label>
        <input
          type="checkbox"
          checked={draft.mute}
          onChange={(event) =>
            setDraft({ ...draft, mute: event.currentTarget.checked })
          }
        />
        {t.mediaMute}
      </label>
      <button type="submit">{t.mediaPlaybackApply}</button>
    </form>
  );
}
