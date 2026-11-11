import { useState } from "react";
import {
  pptxCustomShowCount,
  pptxCustomShowNameUnits,
  pptxCustomShowSlides,
} from "@open-document/wasm/engine-source";
import type {
  PresentationEditor,
  PresentationShowLabels,
} from "../web/presentation-editor.js";
import type { EditorController, UiSnapshot } from "./context.js";
import { messages } from "@open-document/ui/messages";
import { Icon } from "@open-document/ui/icons";
import type { PanelProps } from "./context.js";
import { PptxShowSettings } from "./pptx-show-settings.js";

function showLabels(t: ReturnType<typeof messages>): PresentationShowLabels {
  return {
    title: t.showTitle,
    current: t.showCurrent,
    next: t.showNext,
    previous: t.showPrevious,
    first: t.showFirst,
    last: t.showLast,
    end: t.showEnd,
    saveInk: t.showSaveInk,
    fullscreen: t.showFullscreen,
    presenter: t.showPresenter,
    notes: t.speakerNotes,
    elapsed: t.showElapsed,
    jump: t.showJump,
    pause: t.showPause,
    resume: t.showResume,
    pen: t.showPen,
    penColor: t.showPenColor,
    clearInk: t.showClearInk,
    mediaTitle: t.showMediaTitle,
    mediaPlay: t.showMediaPlay,
    mediaPause: t.showMediaPause,
    mediaStop: t.showMediaStop,
  };
}

export function PptxPresent({ controller, file, state, disabled }: PanelProps) {
  const t = messages(state.locale);
  const { editor } = file;
  return (
    <button
      type="button"
      className="od-slide-present"
      disabled={disabled || editor.query.editView.kind !== "slide"}
      onClick={() =>
        controller.run(() => editor.slideshow.start("current", showLabels(t)))
      }
    >
      <Icon name="play" />
      <span>{t.present}</span>
    </button>
  );
}

export function PptxShow({
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
  const t = messages(state.locale);
  const labels = showLabels(t);
  return (
    <div>
      <PptxShowSettings
        key={editor.query.revision}
        editor={editor}
        controller={controller}
        state={state}
        disabled={disabled}
        labels={labels}
      />
      <button
        type="button"
        disabled={disabled}
        onClick={() =>
          controller.run(() => editor.slideshow.start("first", labels))
        }
      >
        <Icon name="play" />
        {t.showFromFirst}
      </button>
      <button
        type="button"
        disabled={disabled}
        onClick={() =>
          controller.run(() => editor.slideshow.start("current", labels))
        }
      >
        <Icon name="play" />
        {t.showFromCurrent}
      </button>
      <CustomShows
        key={`${editor.query.revision}:${editor.query.slide}`}
        editor={editor}
        controller={controller}
        state={state}
        disabled={disabled}
        labels={labels}
      />
    </div>
  );
}

function CustomShows({
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
  const t = messages(state.locale),
    query = editor.query,
    current = query.customShows;
  const [id, setId] = useState(current.items[0]?.id ?? "");
  const item = current.items.find((item) => item.id === id);
  const [name, setName] = useState(item?.name ?? "");
  const [slides, setSlides] = useState<string[]>(item?.slides ?? [query.slide]);
  const [target, setTarget] = useState(query.slide);
  const apply = (items: typeof current.items) =>
    controller.run(() =>
      editor.editSlides({ action: "customShows", value: items }),
    );
  const move = (index: number, offset: number) => {
    const next = [...slides],
      value = next.splice(index, 1)[0]!;
    next.splice(index + offset, 0, value);
    setSlides(next);
  };
  return (
    <fieldset disabled={disabled}>
      <legend>
        <Icon name="play" />
        {t.customShows}
      </legend>
      <label>
        {t.customShowSelect}
        <select
          aria-label={t.customShowSelect}
          value={id}
          onChange={(event) => {
            const selected = current.items.find(
              (item) => item.id === event.currentTarget.value,
            );
            setId(selected?.id ?? "");
            setName(selected?.name ?? "");
            setSlides(selected?.slides ?? [query.slide]);
          }}
        >
          <option value="">{t.customShowNew}</option>
          {current.items.map((item) => (
            <option key={item.id} value={item.id}>
              {item.name}
            </option>
          ))}
        </select>
      </label>
      <fieldset disabled={!!current.reason}>
        <form
          onSubmit={(event) => {
            event.preventDefault();
            const value = { id, name, slides };
            apply(
              item
                ? current.items.map((old) => (old.id === id ? value : old))
                : [...current.items, value],
            );
          }}
        >
          <label>
            {t.customShowName}
            <input
              required
              maxLength={pptxCustomShowNameUnits}
              value={name}
              onChange={(event) => setName(event.currentTarget.value)}
            />
          </label>
          <ol>
            {slides.map((slide, index) => (
              <li key={index}>
                <span>
                  {query.slides.find((item) => item.id === slide)?.title ??
                    slide}
                </span>
                <button
                  type="button"
                  disabled={index === 0}
                  onClick={() => move(index, -1)}
                >
                  <Icon name="chevron-up" />
                  {t.customShowEarlier}
                </button>
                <button
                  type="button"
                  disabled={index === slides.length - 1}
                  onClick={() => move(index, 1)}
                >
                  <Icon name="chevron-down" />
                  {t.customShowLater}
                </button>
                <button
                  type="button"
                  onClick={() =>
                    setSlides(slides.filter((_, i) => i !== index))
                  }
                >
                  <Icon name="trash" />
                  {t.customShowRemoveSlide}
                </button>
              </li>
            ))}
          </ol>
          <label>
            {t.customShowSlide}
            <select
              aria-label={t.customShowSlide}
              value={target}
              onChange={(event) => setTarget(event.currentTarget.value)}
            >
              {query.slides.map((slide, index) => (
                <option key={slide.id} value={slide.id}>
                  {index + 1}. {slide.title}
                </option>
              ))}
            </select>
          </label>
          <button
            type="button"
            disabled={slides.length >= pptxCustomShowSlides}
            onClick={() => setSlides([...slides, target])}
          >
            <Icon name="plus" />
            {t.customShowAddSlide}
          </button>
          <button
            type="submit"
            disabled={
              !name.trim() ||
              (!item && current.items.length >= pptxCustomShowCount)
            }
          >
            <Icon name="check" />
            {t.customShowApply}
          </button>
        </form>
        <button
          type="button"
          disabled={!item || current.items.length >= pptxCustomShowCount}
          onClick={() => {
            setId("");
            setName(name + " (2)");
          }}
        >
          <Icon name="copy" />
          {t.customShowCopy}
        </button>
        <button
          type="button"
          disabled={!item}
          onClick={() => apply(current.items.filter((item) => item.id !== id))}
        >
          <Icon name="trash" />
          {t.customShowDelete}
        </button>
      </fieldset>
      <button
        type="button"
        disabled={
          !item ||
          !item.slides.some((id) =>
            query.slides.some((slide) => slide.id === id && !slide.hidden),
          )
        }
        onClick={() =>
          controller.run(() => editor.slideshow.start({ show: id }, labels))
        }
      >
        <Icon name="play" />
        {t.customShowStart}
      </button>
      {current.reason && <p>{current.reason}</p>}
    </fieldset>
  );
}
