import { useState } from "react";
import type { PanelProps } from "./panels.js";
import { messages } from "./messages.js";

export function PptxSlideLayout({
  controller,
  state,
  file,
  disabled,
}: PanelProps) {
  const layout =
    file.format === "pptx" ? file.editor.query.slideLayout : undefined;
  const [chosen, setChosen] = useState(layout?.current ?? "");
  if (file.format !== "pptx" || !layout) return null;
  const editor = file.editor,
    t = messages(state.locale);
  const masters = [...new Set(layout.choices.map((choice) => choice.master))];
  return (
    <form
      onSubmit={(event) => {
        event.preventDefault();
        controller.run(() =>
          editor.editSlides({ action: "layout", id: chosen }),
        );
      }}
    >
      <fieldset disabled={disabled || !!layout.reason}>
        <legend>{t.slideLayout}</legend>
        <label>
          {t.chooseSlideLayout}
          <select
            aria-label={t.chooseSlideLayout}
            value={chosen}
            onChange={(event) => setChosen(event.currentTarget.value)}
          >
            {layout.choices.map((choice, index) => (
              <option key={choice.id} value={choice.id}>
                {choice.name || `${t.slideLayout} ${index + 1}`} /{" "}
                {choice.masterName ||
                  `${t.slideMaster} ${masters.indexOf(choice.master) + 1}`}
              </option>
            ))}
          </select>
        </label>
        <button type="submit" disabled={!chosen || chosen === layout.current}>
          {t.applySlideLayout}
        </button>
        <button
          type="button"
          onClick={() =>
            controller.run(() => editor.editSlides({ action: "resetLayout" }))
          }
        >
          {t.resetSlideLayout}
        </button>
      </fieldset>
      {layout.reason && <p>{layout.reason}</p>}
    </form>
  );
}

export function PptxNotes({ controller, state, file, disabled }: PanelProps) {
  const notes = file.format === "pptx" ? file.editor.query.notes : undefined;
  const [text, setText] = useState(notes?.text ?? "");
  if (file.format !== "pptx" || !notes) return null;
  const editor = file.editor,
    t = messages(state.locale);
  return (
    <form
      onSubmit={(event) => {
        event.preventDefault();
        controller.run(() => editor.editSlides({ action: "notes", text }));
      }}
    >
      <fieldset disabled={disabled || !!notes.reason}>
        <legend>{t.speakerNotes}</legend>
        <label>
          {t.speakerNotes}
          <textarea
            aria-label={t.speakerNotes}
            maxLength={32767}
            value={text}
            onChange={(e) => setText(e.currentTarget.value)}
          />
        </label>
        <button type="submit" disabled={text === notes.text}>
          {t.applyNotes}
        </button>
        <button
          type="button"
          disabled={!notes.text}
          onClick={() =>
            controller.run(() =>
              editor.editSlides({ action: "notes", text: "" }),
            )
          }
        >
          {t.clearNotes}
        </button>
      </fieldset>
      {notes.reason && <p>{notes.reason}</p>}
    </form>
  );
}

export function PptxBackground({
  controller,
  state,
  file,
  disabled,
}: PanelProps) {
  const t = messages(state.locale);
  const background =
    file.format === "pptx" ? file.editor.query.background : undefined;
  const [color, setColor] = useState(`#${background?.color ?? "ffffff"}`);
  if (file.format !== "pptx" || !background) return null;
  const editor = file.editor;
  return (
    <form
      onSubmit={(event) => {
        event.preventDefault();
        controller.run(() =>
          editor.editSlides({ action: "background", value: color.slice(1) }),
        );
      }}
    >
      <fieldset disabled={disabled || !!background.reason}>
        <legend>{t.slideBackground}</legend>
        <label>
          {t.slideBackground}
          <input
            type="color"
            value={color}
            onChange={(event) => setColor(event.currentTarget.value)}
          />
        </label>
        <button type="submit" aria-label={`${t.apply} ${t.slideBackground}`}>
          {t.apply}
        </button>
        <button
          type="button"
          disabled={!background.explicit}
          onMouseDown={(event) => event.preventDefault()}
          onClick={() =>
            controller.run(() =>
              editor.editSlides({ action: "background", value: null }),
            )
          }
        >
          {t.inheritStyleProperty}
        </button>
      </fieldset>
      {background.reason && <p>{background.reason}</p>}
    </form>
  );
}

export function PptxSize({ controller, state, file, disabled }: PanelProps) {
  const [width, setWidth] = useState(
    file.format === "pptx" ? String(file.editor.query.width) : "",
  );
  const [height, setHeight] = useState(
    file.format === "pptx" ? String(file.editor.query.height) : "",
  );
  if (file.format !== "pptx") return null;
  const editor = file.editor,
    t = messages(state.locale);
  return (
    <form
      onSubmit={(event) => {
        event.preventDefault();
        controller.run(() =>
          editor.editSlides({
            action: "size",
            width: Number(width),
            height: Number(height),
          }),
        );
      }}
    >
      <fieldset disabled={disabled || !!editor.query.slideSizeReason}>
        <legend>{t.slideSize}</legend>
        <p>{t.scaleSlideContents}</p>
        <label>
          {t.pageWidth}
          <input
            type="number"
            min="1"
            max="14400"
            step="any"
            required
            value={width}
            onChange={(event) => setWidth(event.currentTarget.value)}
          />
        </label>
        <label>
          {t.pageHeight}
          <input
            type="number"
            min="1"
            max="14400"
            step="any"
            required
            value={height}
            onChange={(event) => setHeight(event.currentTarget.value)}
          />
        </label>
        <button
          type="button"
          onClick={() => {
            setWidth("960");
            setHeight("540");
          }}
        >
          16:9
        </button>
        <button
          type="button"
          onClick={() => {
            setWidth("720");
            setHeight("540");
          }}
        >
          4:3
        </button>
        <button type="submit" aria-label={`${t.apply} ${t.slideSize}`}>
          {t.apply}
        </button>
      </fieldset>
      {editor.query.slideSizeReason && <p>{editor.query.slideSizeReason}</p>}
    </form>
  );
}
