import { useState } from "react";
import type { DocumentEditor } from "@open-document/web/editor";
import type { DocxPageBorder } from "@open-document/web/foundation";
import type { EditorController, UiSnapshot } from "./controller.js";
import { messages } from "./messages.js";
import { borderThemeOptions } from "./docx-border-themes.js";

export function DocxCellFill({
  controller,
  state,
  editor,
  fill,
}: {
  controller: EditorController;
  state: UiSnapshot;
  editor: DocumentEditor;
  fill: string | null;
}) {
  const t = messages(state.locale),
    themes = borderThemeOptions(t);
  const [color, setColor] = useState(`#${fill ?? "ffffff"}`);
  const [themeColor, setTheme] = useState<DocxPageBorder["themeColor"]>(null);
  return (
    <form
      onSubmit={(event) => {
        event.preventDefault();
        controller.run(() =>
          editor.editTable({
            action: "cellFill",
            value: color.slice(1),
            themeColor,
          }),
        );
      }}
    >
      <label>
        {t.cellFill}
        <input
          type="color"
          value={color}
          onChange={(event) => {
            setColor(event.currentTarget.value);
            setTheme(null);
          }}
        />
      </label>
      <label>
        {t.themeColorSlot}
        <select
          aria-label={t.themeColorSlot}
          value={themeColor ?? ""}
          onChange={(event) => {
            setTheme(
              themes.find(
                ([slot]) => slot === event.currentTarget.value,
              )?.[0] ?? null,
            );
          }}
        >
          {themes.map(([slot, label]) => (
            <option key={slot ?? "fixed"} value={slot ?? ""}>
              {label}
            </option>
          ))}
        </select>
      </label>
      <button type="submit" aria-label={`${t.apply} ${t.cellFill}`}>
        {t.apply}
      </button>
      <button
        type="button"
        onMouseDown={(event) => event.preventDefault()}
        onClick={() =>
          controller.run(() =>
            editor.editTable({ action: "cellFill", value: null }),
          )
        }
      >
        {t.clearCellFill}
      </button>
    </form>
  );
}
