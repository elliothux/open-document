import { useEffect, useState } from "react";
import type { DocumentEditor } from "@open-document/web/editor";
import type { DocxTracking as Tracking } from "@open-document/web/foundation";
import type { EditorController, UiSnapshot } from "./controller.js";
import { messages } from "./messages.js";

export function DocxTracking({
  controller,
  state,
  editor,
  disabled,
}: {
  controller: EditorController;
  state: UiSnapshot;
  editor: DocumentEditor;
  disabled: boolean;
}) {
  const t = messages(state.locale);
  const [mode, setMode] = useState<Tracking>();
  const [author, setAuthor] = useState("");
  useEffect(() => {
    let active = true;
    controller.run(async () => {
      const value = await editor.tracking();
      if (active) {
        setMode(value);
        setAuthor(value.author);
      }
    });
    return () => {
      active = false;
    };
  }, [controller, editor]);
  const toggle = () =>
    controller.run(async () => {
      await editor.setTracking(mode?.enabled ? null : author);
      setMode(await editor.tracking());
    });
  return (
    <fieldset disabled={disabled || !mode || !!mode.reason}>
      <legend>{t.revisionRecording}</legend>
      <label>
        {t.revisionRecordingAuthor}
        <input
          type="text"
          maxLength={255}
          value={author}
          disabled={mode?.enabled}
          onChange={(event) => setAuthor(event.currentTarget.value)}
        />
      </label>
      <button
        type="button"
        aria-pressed={mode?.enabled ?? false}
        disabled={!mode?.enabled && !author.trim()}
        onClick={toggle}
      >
        {mode?.enabled ? t.revisionRecordingStop : t.revisionRecordingStart}
      </button>
      {mode?.reason && <p role="status">{mode.reason}</p>}
    </fieldset>
  );
}
