import { useState } from "react";
import type { PresentationEditor } from "@open-document/web/presentation-editor";
import type { PptxObjectEdit } from "@open-document/web/pptx";
import type { EditorController, UiSnapshot } from "./controller.js";
import { messages } from "./messages.js";

export function PptxAlignment({
  controller,
  state,
  editor,
  disabled,
}: {
  controller: EditorController;
  state: UiSnapshot;
  editor: PresentationEditor;
  disabled: boolean;
}) {
  const t = messages(state.locale),
    query = editor.query;
  const [relativeTo, setRelativeTo] =
    useState<Extract<PptxObjectEdit, { action: "align" }>["relativeTo"]>(
      "slide",
    );
  const selected = query.objects.filter((object) =>
    query.selection.objects.includes(object.id),
  );
  return (
    <fieldset
      disabled={
        disabled ||
        query.selection.mode !== "object" ||
        !selected.length ||
        selected.some(
          (object) =>
            !object.geometry ||
            object.arrangeReason ||
            object.parent !== selected[0]?.parent,
        )
      }
    >
      <legend>{t.alignObjects}</legend>
      <label>
        {t.alignmentReference}
        <select
          value={relativeTo}
          onChange={(event) => {
            const value = event.currentTarget.value;
            if (
              value === "slide" ||
              value === "selection" ||
              value === "active"
            )
              setRelativeTo(value);
          }}
        >
          <option value="slide">{t.alignToSlide}</option>
          <option value="selection">{t.alignToSelection}</option>
          <option value="active">{t.alignToActive}</option>
        </select>
      </label>
      {(
        [
          ["left", t.alignLeft],
          ["center", t.alignCenter],
          ["right", t.alignRight],
          ["top", t.alignTop],
          ["middle", t.alignMiddle],
          ["bottom", t.alignBottom],
        ] as const
      ).map(([alignment, label]) => (
        <button
          key={alignment}
          type="button"
          onClick={() =>
            controller.run(() =>
              editor.editObjects({ action: "align", alignment, relativeTo }),
            )
          }
        >
          {label}
        </button>
      ))}
      {(
        [
          ["horizontal", t.distributeHorizontal],
          ["vertical", t.distributeVertical],
        ] as const
      ).map(([axis, label]) => (
        <button
          key={axis}
          type="button"
          disabled={
            relativeTo === "active" ||
            selected.length < (relativeTo === "selection" ? 3 : 2)
          }
          onClick={() => {
            if (relativeTo !== "active")
              controller.run(() =>
                editor.editObjects({ action: "distribute", axis, relativeTo }),
              );
          }}
        >
          {label}
        </button>
      ))}
    </fieldset>
  );
}
