import { useLayoutEffect, useState, type ReactNode } from "react";
import type { EditorController, UiSnapshot } from "./controller.js";
import { Command, Group, NativeSlot } from "./controls.js";
import { messages } from "./messages.js";
import type { OwnedFile } from "./types.js";
import { DocxFormatCommands, DocxProperties } from "./docx-format.js";
import { PptxObjects } from "./pptx-objects.js";
import { PptxArrange } from "./pptx-arrange.js";
import { XlsxSheets } from "./xlsx-sheets.js";

interface PanelProps {
  controller: EditorController;
  state: UiSnapshot;
  file: OwnedFile;
  disabled: boolean;
}

export function Navigation({ controller, state, file, disabled }: PanelProps) {
  const t = messages(state.locale);
  const snapshot = file.editor.getSnapshot();
  const page = snapshot.page,
    count = snapshot.pageCount;
  const navigate = (index: number) =>
    controller.run(() => {
      if (file.format === "docx") return file.editor.goToPage(index);
      if (file.format === "pdf") {
        const target = file.editor.snapshot.pages[index];
        if (target) return file.editor.goToPage(target.id);
      }
      if (file.format === "pptx") {
        const target = file.editor.query.slides[index];
        if (target) return file.editor.showSlide(target.id);
      }
      if (file.format === "xlsx") return file.editor.showPrintPage(index);
    });
  return (
    <Group label={t.navigation}>
      <Command
        label={t.previous}
        disabled={disabled || page <= 0}
        action={() => navigate(page - 1)}
      />
      <span>
        {page + 1} / {count}
      </span>
      <Command
        label={t.next}
        disabled={disabled || page + 1 >= count}
        action={() => navigate(page + 1)}
      />
    </Group>
  );
}

export function FormatCommands(props: PanelProps & { tab: string }) {
  const { controller, state, file, disabled, tab } = props;
  const t = messages(state.locale);
  if (file.format === "docx" && tab === "edit")
    return (
      <DocxFormatCommands
        key={file.editor.getSnapshot().documentId}
        controller={controller}
        state={state}
        editor={file.editor}
        disabled={disabled}
      />
    );
  if (file.format === "pptx" && tab === "edit") {
    const editor = file.editor,
      query = editor.query;
    const index = query.slides.findIndex((slide) => slide.id === query.slide);
    const hidden = query.slides[index]?.hidden ?? false;
    return (
      <Group label={t.manageSlides}>
        <Command
          label={t.addSlide}
          disabled={
            disabled || query.slides.length >= 256 || !!query.slideOrderReason
          }
          action={() =>
            controller.run(() => editor.editSlides({ action: "add" }))
          }
        />
        <Command
          label={t.deleteSlide}
          disabled={
            disabled || query.slides.length <= 1 || !!query.slideOrderReason
          }
          action={() =>
            controller.run(() => editor.editSlides({ action: "delete" }))
          }
        />
        <Command
          label={t.slideEarlier}
          disabled={disabled || index <= 0 || !!query.slideOrderReason}
          action={() =>
            controller.run(() =>
              editor.editSlides({ action: "move", index: index - 1 }),
            )
          }
        />
        <Command
          label={t.slideLater}
          disabled={
            disabled ||
            index + 1 >= query.slides.length ||
            !!query.slideOrderReason
          }
          action={() =>
            controller.run(() =>
              editor.editSlides({ action: "move", index: index + 1 }),
            )
          }
        />
        <Command
          label={hidden ? t.showSlide : t.hideSlide}
          disabled={disabled || !!query.slideVisibilityReason}
          action={() =>
            controller.run(() =>
              editor.editSlides({ action: "hidden", hidden: !hidden }),
            )
          }
        />
        {query.slideOrderReason && <p>{query.slideOrderReason}</p>}
        {query.slideVisibilityReason &&
          query.slideVisibilityReason !== query.slideOrderReason && (
            <p>{query.slideVisibilityReason}</p>
          )}
      </Group>
    );
  }
  if (file.format === "xlsx") {
    const data = file.editor.getSnapshot().data;
    return (
      <>
        {tab === "edit" && (
          <Group label={t.edit}>
            <Command
              label={t.clear}
              disabled={disabled}
              action={() => controller.run(() => file.editor.clear())}
            />
          </Group>
        )}
        {tab === "view" && (
          <Group label={t.print}>
            <Command
              label={data.printVisible ? t.closePrint : t.print}
              disabled={disabled}
              action={() =>
                controller.run(() =>
                  data.printVisible
                    ? file.editor.closePrintPreview()
                    : file.editor.printLayout(),
                )
              }
            />
            {data.printVisible && <Navigation {...props} />}
          </Group>
        )}
      </>
    );
  }
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

export function PageList({ controller, state, file, disabled }: PanelProps) {
  const t = messages(state.locale);
  if (file.format !== "pdf" && file.format !== "pptx") return null;
  const pages =
    file.format === "pdf"
      ? file.editor.snapshot.pages.map((page, index) => ({
          id: page.id,
          title: `${t.pages} ${index + 1}`,
        }))
      : file.editor.query.slides.map((slide, index) => ({
          id: slide.id,
          title: `${index + 1}. ${slide.title || t.slide}${slide.hidden ? ` (${t.hiddenSlide})` : ""}`,
        }));
  return (
    <nav
      className="od-sidebar"
      aria-label={file.format === "pdf" ? t.pages : t.slide}
    >
      {pages.map((page, index) => (
        <button
          type="button"
          key={page.id}
          disabled={disabled}
          aria-current={state.document?.page === index ? "page" : undefined}
          onClick={() =>
            controller.run(() =>
              file.format === "pdf"
                ? file.editor.goToPage(page.id)
                : file.editor.showSlide(page.id),
            )
          }
        >
          {page.title}
        </button>
      ))}
    </nav>
  );
}

export function Sheets({ controller, state, file, disabled }: PanelProps) {
  if (file.format !== "xlsx") return null;
  return (
    <XlsxSheets
      key={state.document?.documentId}
      controller={controller}
      state={state}
      editor={file.editor}
      disabled={disabled}
    />
  );
}

export function Properties(props: PanelProps) {
  if (props.file.format === "docx")
    return (
      <DocxProperties
        key={props.file.editor.getSnapshot().documentId}
        controller={props.controller}
        state={props.state}
        editor={props.file.editor}
        disabled={props.disabled}
      />
    );
  if (props.file.format === "pptx") return <SlideProperties {...props} />;
  if (props.file.format === "pdf") return <PdfProperties {...props} />;
  return null;
}

function SlideProperties({ controller, state, file, disabled }: PanelProps) {
  const [dx, setDx] = useState("0"),
    [dy, setDy] = useState("0");
  if (file.format !== "pptx") return null;
  const editor = file.editor,
    t = messages(state.locale),
    query = editor.query;
  const selected = query.objects.find(
    (object) => object.id === query.selection.object,
  );
  return (
    <aside className="od-properties" aria-label={t.objects}>
      <h2>{t.objects}</h2>
      <NativeSlot node={editor.objectList} />
      <div className="flex gap-1" role="group" aria-label={t.edit}>
        <button
          type="button"
          disabled={disabled || !selected}
          aria-pressed={query.selection.mode === "object"}
          onClick={() =>
            controller.run(() => editor.select(query.selection.object))
          }
        >
          {t.objectMode}
        </button>
        <button
          type="button"
          disabled={disabled || !selected || !!selected.textReadOnlyReason}
          aria-pressed={query.selection.mode === "text"}
          onClick={() =>
            controller.run(() => editor.select(query.selection.object, "text"))
          }
        >
          {t.textMode}
        </button>
      </div>
      <p>{selected?.readOnlyReason || selected?.textReadOnlyReason}</p>
      <PptxObjects
        key={state.document?.documentId}
        controller={controller}
        state={state}
        editor={editor}
        disabled={disabled}
      />
      <fieldset disabled={disabled || !selected || !!selected.readOnlyReason}>
        <legend>{t.transform}</legend>
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
          {t.move}
        </button>
        <button
          type="button"
          onClick={() =>
            controller.run(() => editor.transform(Number(dx), Number(dy), 3))
          }
        >
          {t.resize}
        </button>
      </fieldset>
      <PptxArrange
        key={`${state.document?.documentId}:${query.selection.object}:${query.revision}`}
        controller={controller}
        state={state}
        editor={editor}
        disabled={disabled}
      />
    </aside>
  );
}

function PdfProperties({ controller, state, file, disabled }: PanelProps) {
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

export function Zoom({ controller, state, file, disabled }: PanelProps) {
  const t = messages(state.locale);
  return (
    <label className="od-zoom">
      {t.zoom}{" "}
      <select
        aria-label={t.zoom}
        disabled={disabled}
        value={state.document?.zoom ?? 1}
        onChange={(event) =>
          controller.run(() =>
            file.editor.setZoom(Number(event.currentTarget.value)),
          )
        }
      >
        {[0.5, 0.75, 1, 1.25, 1.5, 2].map((zoom) => (
          <option key={zoom} value={zoom}>
            {Math.round(zoom * 100)}%
          </option>
        ))}
      </select>
    </label>
  );
}

export function Details({ state }: { state: UiSnapshot }) {
  const t = messages(state.locale),
    snapshot = state.document;
  const reasons: ReactNode[] = [
    snapshot?.readOnlyReason,
    ...(snapshot?.diagnostics ?? []),
  ].filter(Boolean);
  return reasons.length ? (
    <details>
      <summary>
        {t.diagnostics} ({reasons.length})
      </summary>
      <ul>
        {reasons.map((reason, index) => (
          <li key={index}>{reason}</li>
        ))}
      </ul>
    </details>
  ) : null;
}
