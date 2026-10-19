import { useState } from "react";
import type { PresentationEditor } from "@open-document/web/presentation-editor";
import type { PptxObjectEdit } from "@open-document/web/pptx";
import type { EditorController, UiSnapshot } from "./controller.js";
import { messages } from "./messages.js";

export function PptxDiagram({
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
  const t = messages(state.locale);
  const [template, setTemplate] =
    useState<Extract<PptxObjectEdit, { action: "insertDiagram" }>["template"]>(
      "process",
    );
  const [labels, setLabels] = useState("1\n2\n3");
  return (
    <form
      onSubmit={(event) => {
        event.preventDefault();
        controller.run(() =>
          editor.editObjects({
            action: "insertDiagram",
            template,
            items: labels.split("\n"),
            ...box,
          }),
        );
      }}
    >
      <fieldset disabled={disabled || !!editor.query.readOnlyReason}>
        <legend>{t.insertDiagram}</legend>
        <label>
          {t.diagramTemplate}
          <select
            value={template}
            onChange={(event) => {
              const value = event.currentTarget.value;
              if (
                value === "process" ||
                value === "hierarchy" ||
                value === "cycle"
              )
                setTemplate(value);
            }}
          >
            <option value="process">{t.diagramProcess}</option>
            <option value="hierarchy">{t.diagramHierarchy}</option>
            <option value="cycle">{t.diagramCycle}</option>
          </select>
        </label>
        <label>
          {t.diagramItems}
          <textarea
            value={labels}
            maxLength={32767}
            onChange={(event) => setLabels(event.currentTarget.value)}
          />
        </label>
        <p>{t.diagramShapes}</p>
        <button type="submit">{t.insertDiagram}</button>
      </fieldset>
    </form>
  );
}
