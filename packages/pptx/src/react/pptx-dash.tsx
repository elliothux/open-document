import { useState } from "react";
import type { PresentationEditor } from "../web/presentation-editor.js";
import type { PptxDash } from "../web/pptx.js";
import type { EditorController, UiSnapshot } from "./context.js";
import { messages } from "@open-document/ui/messages";

export function PptxDashFields({
  controller,
  state,
  editor,
  value,
  reason = "",
}: {
  controller: EditorController;
  state: UiSnapshot;
  editor: PresentationEditor;
  value: PptxDash | null;
  reason?: string;
}) {
  const t = messages(state.locale);
  const [dash, setDash] = useState<PptxDash>(value ?? "solid");
  const dashes = [
    ["solid", t.dashSolid],
    ["dash", t.dashRegular],
    ["dashDot", t.dashDot],
    ["dot", t.dashDotted],
    ["lgDash", t.dashLong],
    ["lgDashDot", t.dashLongDot],
    ["lgDashDotDot", t.dashLongDotDot],
    ["sysDash", t.dashSystem],
    ["sysDashDot", t.dashSystemDot],
    ["sysDashDotDot", t.dashSystemDotDot],
    ["sysDot", t.dashSystemDotted],
  ] as const;
  return (
    <fieldset disabled={!!reason}>
      <legend>{t.shapeLineDash}</legend>
      <form
        onSubmit={(event) => {
          event.preventDefault();
          controller.run(() =>
            editor.editObjects({ action: "strokeDash", dash }),
          );
        }}
      >
        <label>
          {t.shapeLineDash}
          <select
            aria-label={t.shapeLineDash}
            value={dash}
            onChange={(event) => {
              const option = dashes.find(
                ([value]) => value === event.currentTarget.value,
              );
              if (option) setDash(option[0]);
            }}
          >
            {dashes.map(([value, label]) => (
              <option key={value} value={value}>
                {label}
              </option>
            ))}
          </select>
        </label>
        <button type="submit">
          {t.apply} {t.shapeLineDash}
        </button>
        <button
          type="button"
          onClick={() =>
            controller.run(() =>
              editor.editObjects({ action: "strokeDash", dash: null }),
            )
          }
        >
          {t.resetLineDash}
        </button>
      </form>
      {reason && <p>{reason}</p>}
    </fieldset>
  );
}
