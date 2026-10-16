import { useState } from "react";
import type { PresentationEditor } from "@open-document/web/presentation-editor";
import type { EditorController, UiSnapshot } from "./controller.js";
import { messages } from "./messages.js";

export function PptxArrange({
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
  const object = query.objects.find(
    (object) => object.id === query.selection.object,
  );
  const [angle, setAngle] = useState(String(object?.geometry?.rotation ?? 0));
  const unavailable =
    disabled ||
    query.selection.objects.length !== 1 ||
    !object ||
    query.selection.mode !== "object" ||
    !!object.arrangeReason;
  return (
    <fieldset disabled={unavailable}>
      <legend>{t.arrangeObjects}</legend>
      <form
        onSubmit={(event) => {
          event.preventDefault();
          controller.run(() =>
            editor.editObjects({ action: "rotate", angle: Number(angle) }),
          );
        }}
      >
        <label>
          {t.objectAngle}
          <input
            type="number"
            min={-360}
            max={360}
            step="any"
            required
            value={angle}
            disabled={!!object?.rotateReason}
            onChange={(event) => setAngle(event.currentTarget.value)}
          />
        </label>
        <button type="submit" disabled={!!object?.rotateReason}>
          {t.applyRotation}
        </button>
      </form>
      {object?.rotateReason && object.rotateReason !== object.arrangeReason && (
        <p>{object.rotateReason}</p>
      )}
      <button
        type="button"
        aria-pressed={object?.geometry?.flipX ?? false}
        onClick={() =>
          controller.run(() =>
            editor.editObjects({ action: "flip", axis: "horizontal" }),
          )
        }
      >
        {t.flipHorizontal}
      </button>
      <button
        type="button"
        aria-pressed={object?.geometry?.flipY ?? false}
        onClick={() =>
          controller.run(() =>
            editor.editObjects({ action: "flip", axis: "vertical" }),
          )
        }
      >
        {t.flipVertical}
      </button>
      {(
        [
          ["front", t.bringFront],
          ["back", t.sendBack],
          ["forward", t.bringForward],
          ["backward", t.sendBackward],
        ] as const
      ).map(([order, label]) => (
        <button
          key={order}
          type="button"
          onClick={() =>
            controller.run(() => editor.editObjects({ action: "layer", order }))
          }
        >
          {label}
        </button>
      ))}
      {object?.arrangeReason && <p>{object.arrangeReason}</p>}
    </fieldset>
  );
}
