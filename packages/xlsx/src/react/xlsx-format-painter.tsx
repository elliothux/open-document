import { useEffect, useRef, useState } from "react";
import type { SpreadsheetEditor } from "../web/spreadsheet-editor.js";
import type { CopiedCellFormat } from "../web/xlsx.js";
import type { EditorController, UiSnapshot } from "./context.js";
import { messages } from "@open-document/ui/messages";

function selection(editor: SpreadsheetEditor): string {
  const {
    sheet,
    selection: { range },
  } = editor.currentState;
  return `${sheet}:${range.top}:${range.left}:${range.bottom}:${range.right}`;
}

export function XlsxFormatPainter({
  controller,
  state,
  editor,
  disabled,
}: {
  controller: EditorController;
  state: UiSnapshot;
  editor: SpreadsheetEditor;
  disabled: boolean;
}) {
  const t = messages(state.locale);
  const active = useRef<
    { format: CopiedCellFormat; selection: string; locked: boolean } | undefined
  >(undefined);
  const pending = useRef<{ cancelled: boolean; locked: boolean } | undefined>(
    undefined,
  );
  const applying = useRef(false);
  const [mode, setMode] = useState("off");
  function cancel() {
    if (pending.current) pending.current.cancelled = true;
    active.current = undefined;
    setMode("off");
  }
  useEffect(() => {
    const root = controller.host.shadowRoot;
    const escape = (event: Event) => {
      if (
        event instanceof KeyboardEvent &&
        event.key === "Escape" &&
        !event.isComposing &&
        (active.current || pending.current)
      ) {
        event.preventDefault();
        event.stopPropagation();
        cancel();
      }
    };
    root?.addEventListener("keydown", escape, true);
    return () => {
      root?.removeEventListener("keydown", escape, true);
      if (pending.current) pending.current.cancelled = true;
      active.current = undefined;
    };
  }, [controller, editor]);
  useEffect(() => {
    const paint = active.current,
      snapshot = state.document;
    if (
      !paint ||
      applying.current ||
      state.loading ||
      !snapshot ||
      snapshot.busy ||
      snapshot.paused ||
      snapshot.composition ||
      snapshot.stopped ||
      snapshot.closed
    )
      return;
    const target = selection(editor);
    if (target === paint.selection) return;
    paint.selection = target;
    applying.current = true;
    if (!paint.locked) cancel();
    controller.run(async () => {
      try {
        await editor.applyFormat(paint.format);
      } finally {
        if (active.current === paint) paint.selection = selection(editor);
        applying.current = false;
      }
    });
  }, [controller, editor, state]);
  return (
    <div>
      <button
        type="button"
        aria-keyshortcuts="Shift+Enter"
        onKeyDown={(event) => {
          if (event.key !== "Enter" || !event.shiftKey) return;
          event.preventDefault();
          if (!active.current && !pending.current) event.currentTarget.click();
          if (pending.current) pending.current.locked = true;
          if (active.current) {
            active.current.locked = true;
            setMode("locked");
          }
        }}
        aria-pressed={mode !== "off"}
        disabled={
          !active.current &&
          !pending.current &&
          (disabled || !!editor.currentState.formatting.readOnlyReason)
        }
        onClick={(event) => {
          if (event.detail >= 2) {
            if (pending.current) pending.current.locked = true;
            if (active.current) {
              active.current.locked = true;
              setMode("locked");
            }
            return;
          }
          if (active.current || pending.current) {
            cancel();
            return;
          }
          const request = { cancelled: false, locked: false };
          pending.current = request;
          controller.run(async () => {
            try {
              const format = await editor.captureFormat();
              if (request.cancelled) return;
              active.current = {
                format,
                selection: selection(editor),
                locked: request.locked,
              };
              setMode(request.locked ? "locked" : "once");
              editor.focus();
            } finally {
              if (pending.current === request) pending.current = undefined;
            }
          });
        }}
      >
        {t.formatPainter}
      </button>
      {mode !== "off" && (
        <p role="status">
          {mode === "locked" ? t.formatPainterLocked : t.formatPainterOnce}
        </p>
      )}
    </div>
  );
}
