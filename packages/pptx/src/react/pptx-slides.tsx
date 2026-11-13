import { useCallback, useEffect, useId, useRef, useState } from "react";
import { RibbonMenu } from "@open-document/ui/ribbon";
import type { PanelProps } from "./context.js";
import { messages } from "@open-document/ui/messages";
import { Icon } from "@open-document/ui/icons";
import { CachedThumbnail, useThumbnails } from "@open-document/ui/thumbnails";
import { slideActions } from "./pptx-slide-actions.js";
import { presentationThumbnailVersion } from "../web/presentation-semantics.js";

export function PptxSlideList(props: PanelProps) {
  const { file, controller, state, disabled, workspace } = props;
  const { editor } = file;
  const t = messages(state.locale),
    query = editor.getSnapshot().data,
    sections = query.sections.items,
    prefix = useId();
  const [collapsed, setCollapsed] = useState<Set<string>>(() => new Set());
  const drag = useRef<{ slide: string; revision: number } | null>(null);
  const [drop, setDrop] = useState<string>();
  const loadThumbnail = useCallback(
    (slide: string, revision: number, signal: AbortSignal) =>
      editor.preview({ slide, revision, signal }),
    [editor],
  );
  const version = useCallback(
    (slide: string) =>
      presentationThumbnailVersion(editor, slide, query.revision),
    [editor, query.revision],
  );
  const thumbnails = useThumbnails(
    loadThumbnail,
    query.slides.map(({ id }) => id),
    query.slide,
    query.revision,
    {
      paused: disabled || !!state.document?.busy || !!state.document?.stopped,
      version,
    },
  );
  const canEdit = state.mode === "edit" && !state.document?.stopped;
  const canMove = canEdit && !disabled && !query.slideOrderReason;
  const active = sections.find((s) => s.slides.includes(query.slide))?.id;
  useEffect(() => {
    drag.current = null;
    setDrop(undefined);
    setCollapsed(new Set());
  }, [editor]);
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
  const indices = new Map(query.slides.map(({ id }, index) => [id, index]));
  const owned = new Set(sections.flatMap((s) => s.slides));
  const page = (id: string) => {
    const index = indices.get(id)!,
      slide = query.slides[index]!;
    const label = `${index + 1}. ${slide.title || t.slide}${slide.hidden ? ` (${t.hiddenSlide})` : ""}`;
    const actions = slideActions(props, index);
    return (
      <div
        className="od-slide-entry"
        key={id}
        data-drop={drop === id || undefined}
        onDragOver={(event) => {
          if (!canMove || !drag.current || drag.current.slide === id) return;
          event.preventDefault();
          event.dataTransfer.dropEffect = "move";
          setDrop(id);
        }}
        onDragLeave={(event) => {
          if (
            !(event.relatedTarget instanceof Node) ||
            !event.currentTarget.contains(event.relatedTarget)
          )
            setDrop(undefined);
        }}
        onDrop={(event) => {
          const source = drag.current;
          if (!canMove || !source || source.slide === id) return;
          event.preventDefault();
          drag.current = null;
          setDrop(undefined);
          controller.run(() =>
            editor.editSlides(
              { action: "move", index },
              source.slide,
              source.revision,
            ),
          );
        }}
      >
        <button
          type="button"
          className="od-slide-select"
          disabled={disabled || !!state.document?.stopped}
          draggable={canMove && query.slides.length > 1}
          aria-keyshortcuts={canMove ? "Alt+ArrowUp Alt+ArrowDown" : undefined}
          aria-current={query.slide === id ? "page" : undefined}
          onClick={() => controller.run(() => editor.showSlide(id))}
          onDragStart={(event) => {
            if (!canMove || editor.getSnapshot().busy) {
              event.preventDefault();
              return;
            }
            drag.current = { slide: id, revision: query.revision };
            event.dataTransfer.effectAllowed = "move";
            event.dataTransfer.setData(
              "application/x-open-document-slide",
              "move",
            );
          }}
          onDragEnd={() => {
            drag.current = null;
            setDrop(undefined);
          }}
          onKeyDown={(event) => {
            if (
              !canMove ||
              !event.altKey ||
              (event.key !== "ArrowUp" && event.key !== "ArrowDown")
            )
              return;
            const target = index + (event.key === "ArrowUp" ? -1 : 1);
            if (target < 0 || target >= query.slides.length) return;
            const { busy, blocking } = editor.getSnapshot();
            if (blocking) return;
            event.preventDefault();
            controller.run(() =>
              editor.editSlides(
                { action: "move", index: target },
                id,
                busy ? undefined : query.revision,
              ),
            );
          }}
        >
          <CachedThumbnail
            cache={thumbnails}
            id={id}
            className="od-slide-preview"
            aspectRatio={query.width / query.height}
          />
          <span>{label}</span>
        </button>
        {canEdit && workspace && (
          <RibbonMenu
            actions={actions}
            label={t.slideActions + " · " + label}
            className="od-slide-menu"
            disabled={disabled}
            portal={workspace.portal}
          >
            <Icon name="more-horizontal" />
          </RibbonMenu>
        )}
      </div>
    );
  };
  return (
    <nav className="od-sidebar od-slide-list" aria-label={t.slide}>
      {sections.length > 0 && (
        <div className="od-section-actions">
          <button
            type="button"
            disabled={disabled}
            onClick={() => setCollapsed(new Set(sections.map((s) => s.id)))}
          >
            <Icon name="chevron-up" />
            {t.collapseSections}
          </button>
          <button
            type="button"
            disabled={disabled}
            onClick={() => setCollapsed(new Set())}
          >
            <Icon name="chevron-down" />
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
              <Icon name={folded ? "chevron-right" : "chevron-down"} />
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

export function PptxViewSelector({
  file,
  controller,
  state,
  disabled,
}: PanelProps) {
  const id = useId();
  const t = messages(state.locale);
  const { editor } = file;
  const { editView, slide } = editor.getSnapshot().data;
  return (
    <>
      <label htmlFor={id}>{t.pptxEditView}</label>
      <select
        id={id}
        value={editView.kind === "slide" ? "" : slide}
        disabled={disabled || !!editView.reason}
        onChange={(event) => {
          const part = event.currentTarget.value || editView.slide;
          controller.run(() => editor.showSlide(part));
        }}
      >
        <option value="">{t.pptxSlideView}</option>
        {(["master", "layout"] as const).map((kind) => (
          <optgroup
            key={kind}
            label={kind === "master" ? t.slideMaster : t.slideLayout}
          >
            {editView.choices
              .filter((choice) => choice.kind === kind)
              .map((choice) => (
                <option key={choice.id} value={choice.id}>
                  {choice.name || choice.id}
                </option>
              ))}
          </optgroup>
        ))}
      </select>
      {editView.reason && <p>{editView.reason}</p>}
    </>
  );
}
