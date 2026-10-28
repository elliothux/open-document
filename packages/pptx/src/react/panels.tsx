export type { PanelProps } from "./context.js";
import type { PanelProps } from "./context.js";
import { Command, Group, NativeSlot } from "@open-document/ui/controls";
import { messages } from "@open-document/ui/messages";
import { PptxDesign } from "./pptx-design.js";
import { PptxGuides, PptxSnapping } from "./pptx-guides.js";
import { PptxObjects } from "./pptx-objects.js";
import { PptxArrange, PptxTransform } from "./pptx-arrange.js";
import { PptxAlignment } from "./pptx-alignment.js";
import { PptxSearch } from "./pptx-search.js";
import { PptxTheme, PptxThemeFonts } from "./pptx-theme.js";
import {
  PptxBackground,
  PptxSize,
  PptxNotes,
  PptxSlideLayout,
} from "./pptx-page.js";
import { PptxFooter } from "./pptx-footer.js";
import { PptxSections } from "./pptx-sections.js";
import { PptxComments } from "./pptx-comments.js";
import { PptxSlideList } from "./pptx-slides.js";
import { PptxTransitionForm } from "./pptx-transition.js";
import { PptxAnimations } from "./pptx-animations.js";
export function FormatCommands(props: PanelProps & { tab: string }) {
  const { controller, state, file, disabled, tab } = props;
  const t = messages(state.locale);
  if (file.format === "pptx" && tab === "edit") {
    const editor = file.editor,
      query = editor.query;
    if (query.editView.kind !== "slide")
      return (
        <>
          <PptxDesign
            key={`source:${file.editor.getSnapshot().documentId}:${query.slide}:${query.editView.choices.find((choice) => choice.id === query.slide)?.name}`}
            controller={controller}
            state={state}
            file={file}
            disabled={disabled}
          />
          <PptxBackground
            key={`${file.editor.getSnapshot().documentId}:${query.slide}:${JSON.stringify(query.background.value)}:${query.background.explicit}`}
            controller={controller}
            state={state}
            file={file}
            disabled={disabled}
          />
        </>
      );
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
          label={t.copySlide}
          disabled={
            disabled || query.slides.length >= 256 || !!query.slideOrderReason
          }
          action={() =>
            controller.run(() => editor.editSlides({ action: "copy" }))
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
        <PptxSections
          key={`sections:${file.editor.getSnapshot().documentId}:${query.slide}:${query.revision}`}
          editor={editor}
          controller={controller}
          state={state}
          disabled={disabled}
        />
        <PptxTransitionForm
          key={`transition:${query.slide}:${query.revision}`}
          editor={editor}
          controller={controller}
          state={state}
          disabled={disabled}
        />
        <PptxAnimations
          key={`animations:${query.slide}:${query.revision}`}
          editor={file.editor}
          controller={controller}
          state={state}
          disabled={disabled}
        />
        <PptxBackground
          key={`${file.editor.getSnapshot().documentId}:${query.slide}:${JSON.stringify(query.background.value)}:${query.background.explicit}`}
          controller={controller}
          state={state}
          file={file}
          disabled={disabled}
        />
        <PptxTheme
          key={`theme:${file.editor.getSnapshot().documentId}`}
          controller={controller}
          state={state}
          file={file}
          disabled={disabled}
        />
        <PptxThemeFonts
          key={`theme-fonts:${file.editor.getSnapshot().documentId}`}
          controller={controller}
          state={state}
          file={file}
          disabled={disabled}
        />
        <PptxSlideLayout
          key={`layout:${file.editor.getSnapshot().documentId}:${query.slide}:${query.slideLayout.current}`}
          controller={controller}
          state={state}
          file={file}
          disabled={disabled}
        />
        <PptxFooter
          key={`footer:${file.editor.getSnapshot().documentId}:${query.slide}:${JSON.stringify(query.footer)}`}
          controller={controller}
          state={state}
          file={file}
          disabled={disabled}
        />
        <PptxNotes
          key={`notes:${file.editor.getSnapshot().documentId}:${query.slide}:${query.notes.text}`}
          controller={controller}
          state={state}
          file={file}
          disabled={disabled}
        />
        <PptxComments
          key={`comments:${file.editor.getSnapshot().documentId}:${query.slide}`}
          controller={controller}
          state={state}
          file={file}
          disabled={disabled}
        />
        <PptxSize
          key={`${file.editor.getSnapshot().documentId}:${query.revision}`}
          controller={controller}
          state={state}
          file={file}
          disabled={disabled}
        />
        <PptxGuides
          key={`guides:${file.editor.getSnapshot().documentId}:${JSON.stringify(query.guides)}`}
          controller={controller}
          state={state}
          file={file}
          disabled={disabled}
        />
        <PptxSnapping
          key={`snapping:${file.editor.getSnapshot().documentId}:${JSON.stringify(query.snapping)}`}
          controller={controller}
          state={state}
          file={file}
          disabled={disabled}
        />
      </Group>
    );
  }
  return null;
}
export function Properties({ controller, state, file, disabled }: PanelProps) {
  if (file.format !== "pptx") return null;
  const editor = file.editor,
    t = messages(state.locale),
    query = editor.query;
  const selected = query.objects.find(
    (object) => object.id === query.selection.object,
  );
  return (
    <aside className="od-properties" aria-label={t.objects}>
      {query.editView.kind === "slide" && (
        <PptxSearch
          key={`search:${state.document?.documentId}`}
          controller={controller}
          state={state}
          editor={editor}
          disabled={disabled}
        />
      )}
      <h2>{t.objects}</h2>
      <NativeSlot node={editor.objectList} />
      <div className="flex gap-1" role="group" aria-label={t.edit}>
        <button
          type="button"
          disabled={disabled || !selected}
          aria-pressed={query.selection.mode === "object"}
          onClick={() =>
            controller.run(() =>
              editor.selectObjects(
                query.selection.objects,
                query.selection.object,
              ),
            )
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
      <PptxTransform
        controller={controller}
        state={state}
        editor={editor}
        disabled={disabled}
      />
      <PptxArrange
        key={`${state.document?.documentId}:${JSON.stringify(query.selection.objects)}:${query.selection.object}:${query.revision}`}
        controller={controller}
        state={state}
        editor={editor}
        disabled={disabled}
      />
      <PptxAlignment
        key={`alignment:${state.document?.documentId}`}
        controller={controller}
        state={state}
        editor={editor}
        disabled={disabled}
      />
    </aside>
  );
}

export function PageList({ controller, state, file, disabled }: PanelProps) {
  if (file.format === "pptx")
    return (
      <PptxSlideList
        key={state.document?.documentId}
        editor={file.editor}
        controller={controller}
        state={state}
        disabled={disabled}
      />
    );
  return null;
}
