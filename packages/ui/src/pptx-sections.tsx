import { useState } from "react";
import type { PresentationEditor } from "@open-document/web/presentation-editor";
import type { PptxSlideEdit } from "@open-document/web/pptx";
import type { EditorController, UiSnapshot } from "./controller.js";
import { messages } from "./messages.js";

export function PptxSections({
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
    sections = query.sections;
  const current = sections.items.find((s) => s.slides.includes(query.slide));
  const [id, setId] = useState(current?.id ?? "");
  const selected = sections.items.find((s) => s.id === id);
  const [name, setName] = useState(selected?.name ?? t.defaultSection);
  const position = sections.items.findIndex((s) => s.id === id);
  const edit = (change: PptxSlideEdit) =>
    controller.run(() => editor.editSlides(change));
  return (
    <fieldset disabled={disabled || !!sections.reason}>
      <legend>{t.sections}</legend>
      <label>
        {t.section}
        <select
          aria-label={t.section}
          value={id}
          onChange={(e) => {
            const value = e.currentTarget.value;
            setId(value);
            setName(
              sections.items.find((s) => s.id === value)?.name ??
                t.defaultSection,
            );
          }}
        >
          <option value="">{t.newSection}</option>
          {sections.items.map((s) => (
            <option key={s.id} value={s.id}>
              {s.name || t.defaultSection} ({s.slides.length})
            </option>
          ))}
        </select>
      </label>
      <label>
        {t.sectionName}
        <input
          aria-label={t.sectionName}
          value={name}
          maxLength={255}
          onChange={(e) => setName(e.currentTarget.value)}
        />
      </label>
      <button
        type="button"
        disabled={sections.items.length >= 256 || !name.trim()}
        onClick={() => edit({ action: "sectionAdd", name })}
      >
        {t.addSection}
      </button>
      <button
        type="button"
        disabled={!selected || !name.trim()}
        onClick={() => edit({ action: "sectionRename", id, name })}
      >
        {t.renameSection}
      </button>
      <button
        type="button"
        disabled={!selected}
        onClick={() => edit({ action: "sectionRemove", id })}
      >
        {t.removeSection}
      </button>
      <button
        type="button"
        disabled={sections.items.length === 0}
        onClick={() => edit({ action: "sectionRemoveAll" })}
      >
        {t.removeAllSections}
      </button>
      <button
        type="button"
        disabled={
          !selected ||
          selected.slides.length >= query.slides.length ||
          !!query.slideOrderReason
        }
        onClick={() => edit({ action: "sectionDelete", id })}
      >
        {t.deleteSectionSlides}
      </button>
      <button
        type="button"
        disabled={!selected || position <= 0 || !!query.slideOrderReason}
        onClick={() => edit({ action: "sectionMove", id, index: position - 1 })}
      >
        {t.sectionEarlier}
      </button>
      <button
        type="button"
        disabled={
          !selected ||
          position + 1 >= sections.items.length ||
          !!query.slideOrderReason
        }
        onClick={() => edit({ action: "sectionMove", id, index: position + 1 })}
      >
        {t.sectionLater}
      </button>
      {sections.reason && <p>{sections.reason}</p>}
    </fieldset>
  );
}
