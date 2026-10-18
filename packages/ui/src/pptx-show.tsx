import type { PresentationEditor } from "@open-document/web/presentation-editor";
import type { EditorController, UiSnapshot } from "./controller.js";
import { messages } from "./messages.js";

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
  const labels = {
    title: t.showTitle,
    current: t.showCurrent,
    next: t.showNext,
    previous: t.showPrevious,
    first: t.showFirst,
    last: t.showLast,
    end: t.showEnd,
    fullscreen: t.showFullscreen,
    presenter: t.showPresenter,
    notes: t.speakerNotes,
    elapsed: t.showElapsed,
    jump: t.showJump,
    pause: t.showPause,
    resume: t.showResume,
  };
  return (
    <div>
      <button
        type="button"
        disabled={disabled}
        onClick={() =>
          controller.run(() => editor.slideshow.start("first", labels))
        }
      >
        {t.showFromFirst}
      </button>
      <button
        type="button"
        disabled={disabled}
        onClick={() =>
          controller.run(() => editor.slideshow.start("current", labels))
        }
      >
        {t.showFromCurrent}
      </button>
    </div>
  );
}
