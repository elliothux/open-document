import { useState } from "react";
import type { PresentationEditor } from "@open-document/web/presentation-editor";
import type { EditorController, UiSnapshot } from "./controller.js";
import { messages } from "./messages.js";

export function PptxPaint({
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
  const objects = query.objects.filter((object) =>
    query.selection.objects.includes(object.id),
  );
  const first = objects[0]?.appearance;
  const [fill, setFill] = useState(`#${first?.fill ?? "336699"}`);
  const [stroke, setStroke] = useState(`#${first?.stroke ?? "000000"}`);
  const [noFill, setNoFill] = useState(first?.fill === null);
  const [noStroke, setNoStroke] = useState(first?.stroke === null);
  const [width, setWidth] = useState(String(first?.width ?? 1));
  const reason = objects.find((object) => object.appearance.reason)?.appearance
    .reason;
  const mixed = objects.some(
    (object) =>
      object.appearance.fill !== first?.fill ||
      object.appearance.stroke !== first?.stroke ||
      object.appearance.width !== first?.width,
  );
  return (
    <fieldset
      disabled={
        disabled ||
        objects.length === 0 ||
        query.selection.mode !== "object" ||
        !!reason
      }
    >
      <legend>{t.shapeAppearance}</legend>
      {mixed && <p>{t.mixed}</p>}
      <form
        onSubmit={(event) => {
          event.preventDefault();
          controller.run(() =>
            editor.editObjects({
              action: "fill",
              color: noFill ? null : fill.slice(1),
            }),
          );
        }}
      >
        <label>
          {t.shapeFill}
          <input
            type="color"
            value={fill}
            disabled={noFill}
            onChange={(event) => setFill(event.currentTarget.value)}
          />
        </label>
        <label>
          <input
            type="checkbox"
            checked={noFill}
            onChange={(event) => setNoFill(event.currentTarget.checked)}
          />
          {t.noShapeFill}
        </label>
        <button type="submit">
          {t.apply} {t.shapeFill}
        </button>
      </form>
      <form
        onSubmit={(event) => {
          event.preventDefault();
          controller.run(() =>
            editor.editObjects({
              action: "stroke",
              color: noStroke ? null : stroke.slice(1),
              width: Number(width),
            }),
          );
        }}
      >
        <label>
          {t.shapeStroke}
          <input
            type="color"
            value={stroke}
            disabled={noStroke}
            onChange={(event) => setStroke(event.currentTarget.value)}
          />
        </label>
        <label>
          {t.shapeLineWidth}
          <input
            type="number"
            min={0.1}
            max={1000}
            step="any"
            required
            value={width}
            onChange={(event) => setWidth(event.currentTarget.value)}
          />
        </label>
        <label>
          <input
            type="checkbox"
            checked={noStroke}
            onChange={(event) => setNoStroke(event.currentTarget.checked)}
          />
          {t.noShapeStroke}
        </label>
        <button type="submit">
          {t.apply} {t.shapeStroke}
        </button>
      </form>
      {reason && <p>{reason}</p>}
    </fieldset>
  );
}
