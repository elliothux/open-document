export type { PanelProps } from "./context.js";
import type { PanelProps } from "./context.js";
import { Command, Group, NativeSlot } from "@open-document/ui/controls";
import { messages } from "@open-document/ui/messages";
import { useLayoutEffect, useState } from "react";
export function FormatCommands(props: PanelProps & { tab: string }) {
  const { controller, state, file, disabled, tab } = props;
  const t = messages(state.locale);
  if (file.format === "pdf") {
    const editor = file.editor;
    const data = editor.getSnapshot().data;
    if (tab === "pages")
      return (
        <Group label={t.pages}>
          <Command
            label={t.earlier}
            disabled={
              disabled ||
              state.document?.page === 0 ||
              !!data.query.pageOrderReason
            }
            action={() => controller.run(() => editor.movePage(-1))}
          />
          <Command
            label={t.later}
            disabled={
              disabled ||
              state.document!.page + 1 >= state.document!.pageCount ||
              !!data.query.pageOrderReason
            }
            action={() => controller.run(() => editor.movePage(1))}
          />
          <Command
            label={t.rotate}
            disabled={disabled}
            action={() => controller.run(() => editor.rotate(90))}
          />
          <button
            type="button"
            className="od-command"
            title={t.deleteHint}
            disabled={
              disabled ||
              data.query.pages.length <= 1 ||
              !!data.query.pageOrderReason
            }
            onClick={() => controller.run(() => editor.deletePage())}
          >
            {t.deletePage}
          </button>
        </Group>
      );
    if (tab === "annotations")
      return (
        <Group label={t.annotations}>
          <Command
            label={t.note}
            disabled={disabled}
            action={() => controller.run(() => editor.beginNote())}
          />
          <Command
            label={t.highlight}
            disabled={
              disabled || !state.document?.selection || state.document.draft
            }
            action={() => controller.run(() => editor.highlight())}
          />
        </Group>
      );
  }
  return null;
}
export function Properties({ controller, state, file, disabled }: PanelProps) {
  const [search, setSearch] = useState("");
  useLayoutEffect(() => {
    if (file.format !== "pdf") return;
    const t = messages(state.locale);
    for (const [key, text] of [
      ["text", t.propertyText],
      ["checked", t.checked],
      ["x", t.noteX],
      ["y", t.noteY],
    ]) {
      const label = file.editor.propertyInput.querySelector(
        `[data-pdf-control="${key}"]`,
      );
      const caption = label?.querySelector("span"),
        input = label?.querySelector("input,textarea");
      if (caption && text) caption.textContent = text;
      if (input && text) input.setAttribute("aria-label", text);
    }
  }, [file, state.locale]);
  if (file.format !== "pdf") return null;
  const editor = file.editor,
    data = editor.getSnapshot().data,
    t = messages(state.locale);
  return (
    <aside className="od-properties" aria-label={`${t.find} / ${t.property}`}>
      <form
        onSubmit={(event) => {
          event.preventDefault();
          controller.run(() => editor.search(search));
        }}
      >
        <label>
          {t.search}
          <input
            type="search"
            value={search}
            onChange={(event) => setSearch(event.currentTarget.value)}
            disabled={disabled}
          />
        </label>
        <button type="submit" disabled={disabled || !search}>
          {t.find}
        </button>
        {data.searching && (
          <button type="button" onClick={() => editor.cancelSearch()}>
            {t.cancelSearch}
          </button>
        )}
        <div role="status">
          {t.matches}: {data.matches.length}
          {data.searching ? ` (${data.searchPage})` : ""}
        </div>
        <button
          type="button"
          disabled={disabled || !data.matches.length}
          onClick={() => controller.run(() => editor.nextMatch(-1))}
        >
          {t.previousMatch}
        </button>
        <button
          type="button"
          disabled={disabled || !data.matches.length}
          onClick={() => controller.run(() => editor.nextMatch())}
        >
          {t.nextMatch}
        </button>
      </form>
      <label>
        {t.property}
        <select
          aria-label={t.property}
          value={data.property === "note" ? "" : data.property}
          disabled={disabled || state.document?.draft}
          onChange={(event) =>
            controller.run(() =>
              editor.chooseProperty(event.currentTarget.value),
            )
          }
        >
          <option value="">{t.choose}</option>
          {data.query.fields.map((field) => (
            <option key={field.id} value={`field:${field.id}`}>
              {field.name || field.id}
            </option>
          ))}
          {data.query.annotations.map((annotation) => (
            <option key={annotation.id} value={`annotation:${annotation.id}`}>
              {annotation.kind}: {annotation.text || annotation.id}
            </option>
          ))}
        </select>
      </label>
      <NativeSlot node={editor.propertyInput} />
      <p>{data.propertyReason}</p>
      <div className="flex gap-1">
        <button
          type="button"
          disabled={
            disabled ||
            !data.property ||
            !!data.propertyReason ||
            data.applying ||
            state.document?.composition
          }
          onClick={() => controller.run(() => editor.applyDraft())}
        >
          {t.applyProperty}
        </button>
        <button
          type="button"
          disabled={
            disabled ||
            !data.property ||
            data.applying ||
            state.document?.composition
          }
          onClick={() => controller.run(() => editor.cancelDraft())}
        >
          {t.cancelProperty}
        </button>
      </div>
      {data.property.startsWith("annotation:") && (
        <button
          type="button"
          disabled={disabled || state.document?.draft || !!data.propertyReason}
          onClick={() => controller.run(() => editor.deleteAnnotation())}
        >
          {t.deleteAnnotation}
        </button>
      )}
    </aside>
  );
}

export function PageList({ controller, state, file, disabled }: PanelProps) {
  const t = messages(state.locale);
  if (file.format !== "pdf") return null;
  const pages = file.editor.snapshot.pages.map((page, index) => ({
    id: page.id,
    title: `${t.pages} ${index + 1}`,
  }));
  return (
    <nav className="od-sidebar" aria-label={t.pages}>
      {pages.map((page, index) => (
        <button
          type="button"
          key={page.id}
          disabled={disabled}
          aria-current={state.document?.page === index ? "page" : undefined}
          onClick={() => controller.run(() => file.editor.goToPage(page.id))}
        >
          {page.title}
        </button>
      ))}
    </nav>
  );
}
