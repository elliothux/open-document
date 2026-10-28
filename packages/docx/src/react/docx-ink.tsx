import { useState } from "react";
import type { DocumentEditor } from "../web/editor.js";
import type { DocxInkTool } from "../web/foundation.js";
import type { EditorController, UiSnapshot } from "./context.js";
import { messages } from "@open-document/ui/messages";

export function DocxInk({
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
  const [options, setOptions] = useState<DocxInkTool>({
    tool: "select",
    color: "174CA0",
    width: 2,
  });
  const apply = (value: DocxInkTool) => {
    setOptions(value);
    controller.run(() => editor.setInkTool(value));
  };
  return (
    <fieldset disabled={disabled}>
      <legend>{t.docxInk}</legend>
      {(
        [
          ["select", t.docxInkSelect],
          ["pen", t.docxInkPen],
          ["highlighter", t.docxInkHighlighter],
          ["eraser", t.docxInkEraser],
        ] as const
      ).map(([tool, label]) => (
        <button
          key={tool}
          type="button"
          aria-pressed={options.tool === tool}
          onClick={() => apply({ ...options, tool })}
        >
          {label}
        </button>
      ))}
      <label>
        {t.docxInkColor}
        <input
          type="color"
          value={`#${options.color}`}
          onChange={(event) =>
            apply({ ...options, color: event.currentTarget.value.slice(1) })
          }
        />
      </label>
      <label>
        {t.docxInkWidth}
        <input
          type="number"
          min={0.5}
          max={24}
          step={0.5}
          value={options.width}
          onChange={(event) => {
            const width = event.currentTarget.valueAsNumber;
            if (Number.isFinite(width) && width >= 0.5 && width <= 24)
              apply({ ...options, width });
          }}
        />
      </label>
    </fieldset>
  );
}
