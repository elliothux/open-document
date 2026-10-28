import { useState } from "react";
import type { PresentationEditor } from "../web/presentation-editor.js";
import type { PptxTransition } from "../web/pptx.js";
import type { EditorController, UiSnapshot } from "./context.js";
import { messages } from "@open-document/ui/messages";

export function PptxTransitionForm({
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
    current = editor.query.transition;
  const [kind, setKind] = useState<PptxTransition["kind"]>(
    current.value?.kind ?? "none",
  );
  const [duration, setDuration] = useState(current.value?.duration || 1000);
  const [direction, setDirection] = useState<PptxTransition["direction"]>(
    current.value?.direction ?? "left",
  );
  const [click, setClick] = useState(current.advance.click);
  const [automatic, setAutomatic] = useState(current.advance.after !== null);
  const [after, setAfter] = useState(current.advance.after ?? 1000);
  return (
    <div>
      <fieldset disabled={disabled || !!current.reason}>
        <legend>{t.transition}</legend>
        <form
          onSubmit={(event) => {
            event.preventDefault();
            controller.run(() =>
              editor.editSlides({
                action: "transition",
                value: {
                  kind,
                  duration: kind === "none" ? 0 : duration,
                  direction: kind === "push" ? direction : "left",
                },
              }),
            );
          }}
        >
          <label>
            {t.transition}
            <select
              aria-label={t.transition}
              value={kind}
              onChange={(event) => {
                const value = event.currentTarget.value;
                if (value === "none" || value === "fade" || value === "push")
                  setKind(value);
              }}
            >
              <option value="none">{t.transitionNone}</option>
              <option value="fade">{t.transitionFade}</option>
              <option value="push">{t.transitionPush}</option>
            </select>
          </label>
          <label>
            {t.transitionDuration}
            <input
              type="number"
              min={100}
              max={60000}
              step={100}
              disabled={kind === "none"}
              value={duration}
              onChange={(event) =>
                setDuration(event.currentTarget.valueAsNumber)
              }
            />
          </label>
          <label>
            {t.transitionDirection}
            <select
              aria-label={t.transitionDirection}
              value={direction}
              disabled={kind !== "push"}
              onChange={(event) => {
                const value = event.currentTarget.value;
                if (
                  value === "left" ||
                  value === "right" ||
                  value === "up" ||
                  value === "down"
                )
                  setDirection(value);
              }}
            >
              <option value="left">{t.alignLeft}</option>
              <option value="right">{t.alignRight}</option>
              <option value="up">{t.alignTop}</option>
              <option value="down">{t.alignBottom}</option>
            </select>
          </label>
          <button type="submit">{t.transitionApply}</button>
          <button
            type="button"
            onClick={() =>
              controller.run(() =>
                editor.editSlides({ action: "transition", value: null }),
              )
            }
          >
            {t.transitionClear}
          </button>
        </form>
        <form
          onSubmit={(event) => {
            event.preventDefault();
            controller.run(() =>
              editor.editSlides({
                action: "advance",
                value: { click, after: automatic ? after : null },
              }),
            );
          }}
        >
          <label>
            <input
              type="checkbox"
              checked={click}
              onChange={(event) => setClick(event.currentTarget.checked)}
            />
            {t.advanceClick}
          </label>
          <label>
            <input
              type="checkbox"
              checked={automatic}
              onChange={(event) => setAutomatic(event.currentTarget.checked)}
            />
            {t.advanceAuto}
          </label>
          <label>
            {t.advanceAfter}
            <input
              type="number"
              min={0}
              max={3600000}
              step={100}
              disabled={!automatic}
              value={after}
              onChange={(event) => setAfter(event.currentTarget.valueAsNumber)}
            />
          </label>
          <button type="submit">{t.advanceApply}</button>
        </form>
      </fieldset>
      {current.reason && <p>{current.reason}</p>}
    </div>
  );
}
