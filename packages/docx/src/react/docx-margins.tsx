import { useState } from "react";
import type { DocumentEditor } from "../web/editor.js";
import type { DocxCellMargins } from "../web/foundation.js";
import type { EditorController, UiSnapshot } from "./context.js";
import { messages } from "@open-document/ui/messages";

export function DocxMargins({
  controller,
  state,
  editor,
  action,
  value,
  label,
  disabled = false,
}: {
  controller: EditorController;
  state: UiSnapshot;
  editor: DocumentEditor;
  action: "cellMargins" | "tableMargins";
  value: Partial<DocxCellMargins>;
  label: string;
  disabled?: boolean;
}) {
  const t = messages(state.locale);
  const [draft, setDraft] = useState({
    top: String(value.top ?? ""),
    right: String(value.right ?? ""),
    bottom: String(value.bottom ?? ""),
    left: String(value.left ?? ""),
  });
  return (
    <form
      onSubmit={(event) => {
        event.preventDefault();
        controller.run(() =>
          editor.editTable({
            action,
            value: {
              top: Number(draft.top),
              right: Number(draft.right),
              bottom: Number(draft.bottom),
              left: Number(draft.left),
            },
          }),
        );
      }}
    >
      <fieldset disabled={disabled}>
        <legend>{label}</legend>
        {(
          [
            ["top", t.pageTop],
            ["right", t.pageRight],
            ["bottom", t.pageBottom],
            ["left", t.pageLeft],
          ] as const
        ).map(([side, label]) => (
          <label key={side}>
            {label}
            <input
              type="number"
              min={0}
              max={14400}
              step={0.05}
              required
              value={draft[side]}
              placeholder={value[side] === undefined ? t.mixed : undefined}
              onChange={(event) =>
                setDraft({ ...draft, [side]: event.currentTarget.value })
              }
            />
          </label>
        ))}
        <button
          type="submit"
          aria-label={`${t.apply} ${label}`}
          disabled={Object.values(draft).some((value) => value === "")}
        >
          {t.apply}
        </button>
        <button
          type="button"
          onMouseDown={(event) => event.preventDefault()}
          onClick={() =>
            controller.run(() => editor.editTable({ action, value: null }))
          }
        >
          {action === "cellMargins"
            ? t.resetCellMargins
            : t.inheritStyleProperty}
        </button>
      </fieldset>
    </form>
  );
}
