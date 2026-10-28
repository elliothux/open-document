import { useEffect, useId, useState } from "react";
import type { PresentationEditor } from "../web/presentation-editor.js";
import type { EditorController, UiSnapshot } from "./context.js";
import { messages } from "@open-document/ui/messages";
import { PptxShow } from "./pptx-show.js";
import { PptxImport } from "./pptx-import.js";

export function PptxSlideList({
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
    sections = query.sections.items,
    prefix = useId();
  const [collapsed, setCollapsed] = useState<Set<string>>(() => new Set());
  const active = sections.find((s) => s.slides.includes(query.slide))?.id;
  useEffect(() => {
    setCollapsed((previous) => {
      const next = new Set(
        [...previous].filter((id) => sections.some((s) => s.id === id)),
      );
      return next.size === previous.size ? previous : next;
    });
  }, [sections]);
  useEffect(() => {
    if (!active) return;
    setCollapsed((previous) => {
      if (!previous.has(active)) return previous;
      const next = new Set(previous);
      next.delete(active);
      return next;
    });
  }, [query.slide, active]);
  const owned = new Set(sections.flatMap((s) => s.slides));
  const page = (id: string) => {
    const index = query.slides.findIndex((s) => s.id === id),
      slide = query.slides[index]!;
    return (
      <button
        type="button"
        key={id}
        disabled={disabled}
        aria-current={query.slide === id ? "page" : undefined}
        onClick={() => controller.run(() => editor.showSlide(id))}
      >
        {`${index + 1}. ${slide.title || t.slide}${slide.hidden ? ` (${t.hiddenSlide})` : ""}`}
      </button>
    );
  };
  return (
    <nav className="od-sidebar" aria-label={t.slide}>
      <label htmlFor={`${prefix}-view`}>{t.pptxEditView}</label>
      <select
        id={`${prefix}-view`}
        value={query.editView.kind === "slide" ? "" : query.slide}
        disabled={disabled || !!query.editView.reason}
        onChange={(event) => {
          const part = event.currentTarget.value || query.editView.slide;
          controller.run(() => editor.showSlide(part));
        }}
      >
        <option value="">{t.pptxSlideView}</option>
        {(["master", "layout"] as const).map((kind) => (
          <optgroup
            key={kind}
            label={kind === "master" ? t.slideMaster : t.slideLayout}
          >
            {query.editView.choices
              .filter((choice) => choice.kind === kind)
              .map((choice) => (
                <option key={choice.id} value={choice.id}>
                  {choice.name || choice.id}
                </option>
              ))}
          </optgroup>
        ))}
      </select>
      {query.editView.reason && <p>{query.editView.reason}</p>}
      <PptxImport
        editor={editor}
        controller={controller}
        state={state}
        disabled={disabled}
      />
      {query.editView.kind === "slide" && (
        <PptxShow
          editor={editor}
          controller={controller}
          state={state}
          disabled={disabled}
        />
      )}
      {sections.length > 0 && (
        <div className="od-section-actions">
          <button
            type="button"
            disabled={disabled}
            onClick={() => setCollapsed(new Set(sections.map((s) => s.id)))}
          >
            {t.collapseSections}
          </button>
          <button
            type="button"
            disabled={disabled}
            onClick={() => setCollapsed(new Set())}
          >
            {t.expandSections}
          </button>
        </div>
      )}
      {query.slides.filter((s) => !owned.has(s.id)).map((s) => page(s.id))}
      {sections.map((section) => {
        const folded = collapsed.has(section.id),
          name = section.name || t.defaultSection,
          id = `${prefix}-${section.id}`;
        return (
          <div key={section.id} role="group" aria-label={name}>
            <button
              type="button"
              className="od-section-heading"
              disabled={disabled}
              aria-expanded={!folded}
              aria-controls={id}
              aria-current={
                folded && active === section.id ? "true" : undefined
              }
              onClick={() =>
                setCollapsed((previous) => {
                  const next = new Set(previous);
                  if (next.has(section.id)) next.delete(section.id);
                  else next.add(section.id);
                  return next;
                })
              }
            >
              <span aria-hidden="true">{folded ? "▸" : "▾"} </span>
              {name} ({section.slides.length})
            </button>
            <div id={id} className="od-section-pages" hidden={folded}>
              {section.slides.map(page)}
            </div>
          </div>
        );
      })}
    </nav>
  );
}
