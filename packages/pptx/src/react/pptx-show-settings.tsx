import { useState } from "react";
import type {
  PresentationEditor,
  PresentationShowLabels,
} from "../web/presentation-editor.js";
import type { PptxQuery } from "../web/pptx.js";
import type { EditorController, UiSnapshot } from "./context.js";

const en = {
  title: "Slideshow settings",
  selection: "Default show slides",
  all: "All slides",
  range: "Slide range",
  custom: "Custom show",
  first: "First slide number",
  last: "Last slide number",
  name: "Default custom show",
  timings: "Use slide timings",
  animations: "Show object animations",
  loop: "Loop slideshow",
  apply: "Apply slideshow settings",
  start: "Start configured slideshow",
};
const zh: typeof en = {
  title: "放映设置",
  selection: "默认放映内容",
  all: "全部幻灯片",
  range: "幻灯片范围",
  custom: "自定义放映",
  first: "起始页码",
  last: "结束页码",
  name: "默认自定义放映",
  timings: "使用换页计时",
  animations: "显示对象动画",
  loop: "循环放映",
  apply: "应用放映设置",
  start: "按设置开始放映",
};
type Settings = NonNullable<PptxQuery["showSettings"]["value"]>;
export function PptxShowSettings({
  editor,
  controller,
  state,
  disabled,
  labels,
}: {
  editor: PresentationEditor;
  controller: EditorController;
  state: UiSnapshot;
  disabled: boolean;
  labels: PresentationShowLabels;
}) {
  const current = editor.query.showSettings;
  const t = state.locale === "zh-CN" ? zh : en;
  const [draft, setDraft] = useState<Settings>(
    current.value ?? {
      slides: { kind: "all" },
      timings: true,
      animations: true,
      loop: false,
    },
  );
  return (
    <fieldset disabled={disabled}>
      <legend>{t.title}</legend>
      <form
        onSubmit={(event) => {
          event.preventDefault();
          controller.run(() =>
            editor.editSlides({ action: "showSettings", value: draft }),
          );
        }}
      >
        <fieldset disabled={!!current.reason}>
          <label>
            {t.selection}
            <select
              aria-label={t.selection}
              value={draft.slides.kind}
              onChange={(event) =>
                setDraft({
                  ...draft,
                  slides:
                    event.currentTarget.value === "range"
                      ? {
                          kind: "range",
                          first: 1,
                          last: editor.query.slides.length,
                        }
                      : event.currentTarget.value === "custom"
                        ? {
                            kind: "custom",
                            id: editor.query.customShows.items[0]?.id ?? "",
                          }
                        : { kind: "all" },
                })
              }
            >
              <option value="all">{t.all}</option>
              <option value="range">{t.range}</option>
              <option
                value="custom"
                disabled={!editor.query.customShows.items.length}
              >
                {t.custom}
              </option>
            </select>
          </label>
          {draft.slides.kind === "range" && (
            <>
              <label>
                {t.first}
                <input
                  type="number"
                  required
                  min={1}
                  max={draft.slides.last}
                  step={1}
                  value={draft.slides.first}
                  onChange={(event) => {
                    if (draft.slides.kind === "range")
                      setDraft({
                        ...draft,
                        slides: {
                          ...draft.slides,
                          first: Number(event.currentTarget.value),
                        },
                      });
                  }}
                />
              </label>
              <label>
                {t.last}
                <input
                  type="number"
                  required
                  min={draft.slides.first}
                  max={editor.query.slides.length}
                  step={1}
                  value={draft.slides.last}
                  onChange={(event) => {
                    if (draft.slides.kind === "range")
                      setDraft({
                        ...draft,
                        slides: {
                          ...draft.slides,
                          last: Number(event.currentTarget.value),
                        },
                      });
                  }}
                />
              </label>
            </>
          )}
          {draft.slides.kind === "custom" && (
            <label>
              {t.name}
              <select
                aria-label={t.name}
                value={draft.slides.id}
                onChange={(event) =>
                  setDraft({
                    ...draft,
                    slides: { kind: "custom", id: event.currentTarget.value },
                  })
                }
              >
                {editor.query.customShows.items.map((show) => (
                  <option key={show.id} value={show.id}>
                    {show.name}
                  </option>
                ))}
              </select>
            </label>
          )}
          {(["timings", "animations", "loop"] as const).map((key) => (
            <label key={key}>
              <input
                type="checkbox"
                checked={draft[key]}
                onChange={(event) =>
                  setDraft({ ...draft, [key]: event.currentTarget.checked })
                }
              />
              {t[key]}
            </label>
          ))}
          <button type="submit">{t.apply}</button>
        </fieldset>
      </form>
      <button
        type="button"
        disabled={!current.value}
        onClick={() =>
          controller.run(() => editor.slideshow.start("settings", labels))
        }
      >
        {t.start}
      </button>
      {current.reason && <p>{current.reason}</p>}
    </fieldset>
  );
}
