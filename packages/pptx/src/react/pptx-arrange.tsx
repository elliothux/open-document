import { useState } from "react";
import type { PresentationEditor } from "../web/presentation-editor.js";
import type { EditorController, UiSnapshot } from "./context.js";
import { Icon } from "@open-document/ui/icons";
import { messages } from "@open-document/ui/messages";

type Props = {
  controller: EditorController;
  state: UiSnapshot;
  editor: PresentationEditor;
  disabled: boolean;
};

export function PptxTransform({ controller, state, editor, disabled }: Props) {
  const [dx, setDx] = useState("0"),
    [dy, setDy] = useState("0");
  const t = messages(state.locale),
    query = editor.query;
  const selected = query.objects.filter((object) =>
    query.selection.objects.includes(object.id),
  );
  return (
    <fieldset
      disabled={
        disabled ||
        query.selection.mode !== "object" ||
        selected.length === 0 ||
        selected.some(
          (object) =>
            object.transformReason || object.parent !== selected[0]?.parent,
        )
      }
    >
      <legend>
        <Icon name="move" />
        {t.transform}
      </legend>
      <label>
        {t.deltaX}
        <input
          type="number"
          value={dx}
          onChange={(event) => setDx(event.currentTarget.value)}
        />
      </label>
      <label>
        {t.deltaY}
        <input
          type="number"
          value={dy}
          onChange={(event) => setDy(event.currentTarget.value)}
        />
      </label>
      <button
        type="button"
        onClick={() =>
          controller.run(() => editor.transform(Number(dx), Number(dy)))
        }
      >
        <Icon name="move" />
        {t.move}
      </button>
      <button
        type="button"
        onClick={() =>
          controller.run(() => editor.transform(Number(dx), Number(dy), 3))
        }
      >
        <Icon name="ruler" />
        {t.resize}
      </button>
    </fieldset>
  );
}

export function PptxArrange({ controller, state, editor, disabled }: Props) {
  const t = messages(state.locale),
    query = editor.query;
  const object = query.objects.find(
    (object) => object.id === query.selection.object,
  );
  const objects = query.objects.filter((object) =>
    query.selection.objects.includes(object.id),
  );
  const rotation = object?.geometry?.rotation;
  const [angle, setAngle] = useState(
    objects.every((object) => object.geometry?.rotation === rotation)
      ? String(rotation ?? 0)
      : "",
  );
  const reason = objects.find((object) => object.arrangeReason)?.arrangeReason;
  const transformReason = objects.find(
    (object) => object.transformReason,
  )?.transformReason;
  const rotateReason = objects.find(
    (object) => object.rotateReason,
  )?.rotateReason;
  const table = objects.some((object) => object.kind === "table");
  const unavailable =
    disabled ||
    !object ||
    query.selection.mode !== "object" ||
    !!transformReason ||
    objects.some((item) => item.parent !== object.parent);
  return (
    <fieldset disabled={unavailable}>
      <legend>
        <Icon name="layers" />
        {t.arrangeObjects}
      </legend>
      <div className="od-pptx-arrange-actions">
        {(
          [
            ["front", t.bringFront, "bring-to-front"],
            ["back", t.sendBack, "send-to-back"],
            ["forward", t.bringForward, "bring-forward"],
            ["backward", t.sendBackward, "send-backward"],
          ] as const
        ).map(([order, label, icon]) => (
          <button
            key={order}
            type="button"
            disabled={!!reason}
            title={reason}
            onClick={() =>
              controller.run(() =>
                editor.editObjects({ action: "layer", order }),
              )
            }
          >
            <Icon name={icon} />
            <span>{label}</span>
          </button>
        ))}
      </div>
      {reason && <p>{reason}</p>}
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
            placeholder={t.mixed}
            disabled={!!rotateReason}
            onChange={(event) => setAngle(event.currentTarget.value)}
          />
        </label>
        <button type="submit" disabled={!!rotateReason}>
          <Icon name="check" />
          {t.applyRotation}
        </button>
      </form>
      {rotateReason && rotateReason !== reason && <p>{rotateReason}</p>}
      <button
        type="button"
        disabled={table}
        title={table ? rotateReason : undefined}
        aria-pressed={
          objects.every(
            (item) => item.geometry?.flipX === object?.geometry?.flipX,
          )
            ? (object?.geometry?.flipX ?? false)
            : "mixed"
        }
        onClick={() =>
          controller.run(() =>
            editor.editObjects({ action: "flip", axis: "horizontal" }),
          )
        }
      >
        <Icon name="move" />
        {t.flipHorizontal}
      </button>
      <button
        type="button"
        disabled={table}
        title={table ? rotateReason : undefined}
        aria-pressed={
          objects.every(
            (item) => item.geometry?.flipY === object?.geometry?.flipY,
          )
            ? (object?.geometry?.flipY ?? false)
            : "mixed"
        }
        onClick={() =>
          controller.run(() =>
            editor.editObjects({ action: "flip", axis: "vertical" }),
          )
        }
      >
        <Icon name="move" />
        {t.flipVertical}
      </button>
    </fieldset>
  );
}
