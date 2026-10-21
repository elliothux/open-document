import { useState } from "react";
import type { EditorController, UiSnapshot } from "./controller.js";
import { messages } from "./messages.js";

export function WordArt({
  apply,
  controller,
  state,
  disabled,
}: {
  apply: (
    preset: "blue" | "gold" | "red" | "purple" | "green-italic",
    text: string,
  ) => Promise<void>;
  controller: EditorController;
  state: UiSnapshot;
  disabled: boolean;
}) {
  const t = messages(state.locale);
  const [preset, setPreset] = useState<Parameters<typeof apply>[0]>("blue");
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
          await apply(preset, text);
        });
      }}
    >
      <fieldset disabled={disabled}>
        <legend>{t.insertWordArt}</legend>
        <label>
          {t.wordArtPreset}
          <select
            aria-label={t.wordArtPreset}
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
