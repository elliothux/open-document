import { useState } from "react";
import type { PresentationEditor } from "@open-document/web/presentation-editor";
import type { PptxObjectEdit } from "@open-document/web/pptx";
import type { EditorController, UiSnapshot } from "./controller.js";
import { messages } from "./messages.js";

export function PptxWordArt({
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
  const t = messages(state.locale);
  const [preset, setPreset] =
    useState<Extract<PptxObjectEdit, { action: "insertWordArt" }>["preset"]>(
      "blue",
    );
  const [text, setText] = useState("");
  const presets = {
    blue: t.wordArtBlue,
    gold: t.wordArtGold,
    red: t.wordArtRed,
    purple: t.wordArtPurple,
    "green-italic": t.wordArtGreenItalic,
  };
  return (
    <form
      onSubmit={(event) => {
        event.preventDefault();
        controller.run(async () => {
          await editor.editObjects({ action: "insertWordArt", preset, text });
          editor.focus();
        });
      }}
    >
      <fieldset disabled={disabled || !!editor.query.readOnlyReason}>
        <legend>{t.insertWordArt}</legend>
        <label>
          {t.wordArtPreset}
          <select
            value={preset}
            onChange={(event) => {
              const value = event.currentTarget.value;
              if (
                value === "blue" ||
                value === "gold" ||
                value === "red" ||
                value === "purple" ||
                value === "green-italic"
              )
                setPreset(value);
            }}
          >
            {Object.entries(presets).map(([value, label]) => (
              <option key={value} value={value}>
                {label}
              </option>
            ))}
          </select>
        </label>
        <label>
          {t.wordArtText}
          <textarea
            required
            maxLength={32767}
            value={text}
            onChange={(event) => setText(event.currentTarget.value)}
          />
        </label>
        <button type="submit" disabled={!text.trim()}>
          {t.insertWordArt}
        </button>
      </fieldset>
    </form>
  );
}
