import { useState } from "react";
import type { PresentationEditor } from "../web/presentation-editor.js";
import type { PptxObjectEdit } from "../web/pptx.js";
import type { EditorController, UiSnapshot } from "./context.js";
import { Icon } from "@open-document/ui/icons";
import { messages } from "@open-document/ui/messages";

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
      <legend>
        <Icon name="align-objects-center" />
        {t.alignObjects}
      </legend>
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
      <div className="od-pptx-arrange-actions">
        {(
          [
            ["left", t.alignLeft, "align-objects-left"],
            ["center", t.alignCenter, "align-objects-center"],
            ["right", t.alignRight, "align-objects-right"],
            ["top", t.alignTop, "align-vertical-top"],
            ["middle", t.alignMiddle, "align-vertical-center"],
            ["bottom", t.alignBottom, "align-vertical-bottom"],
          ] as const
        ).map(([alignment, label, icon]) => (
          <button
            key={alignment}
            type="button"
            onClick={() =>
              controller.run(() =>
                editor.editObjects({ action: "align", alignment, relativeTo }),
              )
            }
          >
            <Icon name={icon} />
            <span>{label}</span>
          </button>
        ))}
        {(
          [
            ["horizontal", t.distributeHorizontal, "distribute-horizontal"],
            ["vertical", t.distributeVertical, "distribute-vertical"],
          ] as const
        ).map(([axis, label, icon]) => (
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
                  editor.editObjects({
                    action: "distribute",
                    axis,
                    relativeTo,
                  }),
                );
            }}
          >
            <Icon name={icon} />
            <span>{label}</span>
          </button>
        ))}
      </div>
    </fieldset>
  );
}
