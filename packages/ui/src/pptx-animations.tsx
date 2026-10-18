import { useState } from "react";
import type { PresentationEditor } from "@open-document/web/presentation-editor";
import type { PptxAnimation } from "@open-document/web/pptx";
import type { EditorController, UiSnapshot } from "./controller.js";
import { messages } from "./messages.js";

export function PptxAnimations({
  editor,
  controller,
  state,
  disabled,
}: {
  editor: PresentationEditor;
  controller: EditorController;
  state: UiSnapshot;
  disabled: boolean;
}) {
  const t = messages(state.locale),
    query = editor.query,
    current = query.animations;
  const targets = query.objects.filter(
    (object) =>
      !object.parent &&
      ["shape", "image"].includes(object.kind) &&
      object.id.startsWith(`${query.slide}#`),
  );
  const [object, setObject] = useState(
    targets.find((target) => target.id === query.selection.object)?.id ??
      targets[0]?.id ??
      "",
  );
  const [kind, setKind] = useState<PptxAnimation["kind"]>("appear");
  const [trigger, setTrigger] = useState<PptxAnimation["trigger"]>("click");
  const [delay, setDelay] = useState(0);
  const [duration, setDuration] = useState(1000);
  const [repeat, setRepeat] = useState(1);
  const [params, setParams] = useState<number[]>([]);
  const [editing, setEditing] = useState<number>();
  const timed = kind !== "appear" && kind !== "disappear";
  const flight = kind === "flyIn" || kind === "flyOut";
  const names = {
    appear: t.animationAppear,
    disappear: t.animationDisappear,
    fadeIn: t.animationFadeIn,
    fadeOut: t.animationFadeOut,
    scale: t.animationScale,
    rotate: t.animationRotate,
    move: t.animationMove,
    flyIn: t.animationFlyIn,
    flyOut: t.animationFlyOut,
  };
  const apply = (items: PptxAnimation[]) =>
    controller.run(() =>
      editor.editSlides({ action: "animations", value: items }),
    );
  const move = (index: number, offset: number) => {
    const items = [...current.items],
      next = index + offset;
    const item = items.splice(index, 1)[0]!;
    items.splice(next, 0, item);
    apply(items);
  };
  return (
    <fieldset disabled={disabled || !!current.reason}>
      <legend>{t.animations}</legend>
      <ol>
        {current.items.map((item, index) => (
          <li key={index}>
            <span>
              {query.objects.find((target) => target.id === item.object)
                ?.name ?? item.object}
              : {names[item.kind]}
            </span>
            <button
              type="button"
              onClick={() => {
                setEditing(index);
                setObject(item.object);
                setKind(item.kind);
                setTrigger(item.trigger);
                setDelay(item.delay);
                setDuration(item.duration === 1 ? 1000 : item.duration);
                setRepeat(item.repeat);
                setParams(item.params);
              }}
            >
              {t.animationEdit}
            </button>
            <button
              type="button"
              disabled={index === 0}
              onClick={() => move(index, -1)}
            >
              {t.animationEarlier}
            </button>
            <button
              type="button"
              disabled={index === current.items.length - 1}
              onClick={() => move(index, 1)}
            >
              {t.animationLater}
            </button>
            <button
              type="button"
              onClick={() => apply(current.items.filter((_, i) => i !== index))}
            >
              {t.animationRemove}
            </button>
          </li>
        ))}
      </ol>
      <form
        onSubmit={(event) => {
          event.preventDefault();
          const value: PptxAnimation = {
            object,
            kind,
            trigger,
            delay,
            duration: timed ? duration : 1,
            repeat: timed ? repeat : 1,
            params,
          };
          apply(
            editing === undefined
              ? [...current.items, value]
              : current.items.map((item, index) =>
                  index === editing ? value : item,
                ),
          );
        }}
      >
        <label>
          {t.animationTarget}
          <select
            aria-label={t.animationTarget}
            value={object}
            onChange={(event) => setObject(event.currentTarget.value)}
          >
            {targets.map((target) => (
              <option key={target.id} value={target.id}>
                {target.name}
              </option>
            ))}
          </select>
        </label>
        <label>
          {t.animationEffect}
          <select
            aria-label={t.animationEffect}
            value={kind}
            onChange={(event) => {
              const value = event.currentTarget.value;
              if (
                value === "appear" ||
                value === "disappear" ||
                value === "fadeIn" ||
                value === "fadeOut" ||
                value === "scale" ||
                value === "rotate" ||
                value === "move" ||
                value === "flyIn" ||
                value === "flyOut"
              ) {
                setKind(value);
                setParams(
                  value === "scale"
                    ? [150, 150]
                    : value === "rotate"
                      ? [90]
                      : value === "move"
                        ? [100, 0]
                        : value === "flyIn" || value === "flyOut"
                          ? [8]
                          : [],
                );
              }
            }}
          >
            <option value="appear">{t.animationAppear}</option>
            <option value="disappear">{t.animationDisappear}</option>
            <option value="fadeIn">{t.animationFadeIn}</option>
            <option value="fadeOut">{t.animationFadeOut}</option>
            <option value="scale">{t.animationScale}</option>
            <option value="rotate">{t.animationRotate}</option>
            <option value="move">{t.animationMove}</option>
            <option value="flyIn">{t.animationFlyIn}</option>
            <option value="flyOut">{t.animationFlyOut}</option>
          </select>
        </label>
        {flight ? (
          <label>
            {t.animationDirection}
            <select
              aria-label={t.animationDirection}
              value={params[0]}
              onChange={(event) =>
                setParams([Number(event.currentTarget.value)])
              }
            >
              <option value={8}>{t.flightLeft}</option>
              <option value={2}>{t.flightRight}</option>
              <option value={1}>{t.flightTop}</option>
              <option value={4}>{t.flightBottom}</option>
              <option value={9}>{t.flightTopLeft}</option>
              <option value={3}>{t.flightTopRight}</option>
              <option value={12}>{t.flightBottomLeft}</option>
              <option value={6}>{t.flightBottomRight}</option>
            </select>
          </label>
        ) : (
          params.map((value, index) => (
            <label key={index}>
              {kind === "scale"
                ? index === 0
                  ? t.animationScaleX
                  : t.animationScaleY
                : kind === "rotate"
                  ? t.animationAngle
                  : index === 0
                    ? t.animationMoveX
                    : t.animationMoveY}
              <input
                type="number"
                required
                step={1}
                min={kind === "scale" ? 1 : kind === "rotate" ? -3600 : -14400}
                max={kind === "scale" ? 1000 : kind === "rotate" ? 3600 : 14400}
                value={value}
                onChange={(event) =>
                  setParams(
                    params.map((item, i) =>
                      i === index ? event.currentTarget.valueAsNumber : item,
                    ),
                  )
                }
              />
            </label>
          ))
        )}
        <label>
          {t.animationTrigger}
          <select
            aria-label={t.animationTrigger}
            value={trigger}
            onChange={(event) => {
              const value = event.currentTarget.value;
              if (value === "click" || value === "with" || value === "after")
                setTrigger(value);
            }}
          >
            <option value="click">{t.animationClick}</option>
            <option value="with">{t.animationWith}</option>
            <option value="after">{t.animationAfter}</option>
          </select>
        </label>
        <label>
          {t.animationDelay}
          <input
            type="number"
            min={0}
            max={60000}
            step={1}
            value={delay}
            onChange={(event) => setDelay(event.currentTarget.valueAsNumber)}
          />
        </label>
        <label>
          {t.animationDuration}
          <input
            type="number"
            min={timed ? 100 : 1}
            max={60000}
            step={1}
            value={timed ? duration : 1}
            disabled={!timed}
            onChange={(event) => setDuration(event.currentTarget.valueAsNumber)}
          />
        </label>
        <label>
          {t.animationRepeat}
          <input
            type="number"
            min={1}
            max={100}
            step={1}
            value={timed ? repeat : 1}
            disabled={!timed}
            onChange={(event) => setRepeat(event.currentTarget.valueAsNumber)}
          />
        </label>
        <button
          type="submit"
          disabled={
            !object || (editing === undefined && current.items.length >= 128)
          }
        >
          {editing === undefined ? t.animationAdd : t.animationApply}
        </button>
        {editing !== undefined && (
          <button type="button" onClick={() => setEditing(undefined)}>
            {t.animationCancel}
          </button>
        )}
      </form>
      {current.reason && <p>{current.reason}</p>}
    </fieldset>
  );
}
