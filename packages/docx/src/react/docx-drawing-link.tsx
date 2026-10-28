import { useState } from "react";
import type { EditorController, UiSnapshot } from "./context.js";
import { messages } from "@open-document/ui/messages";

export function DocxDrawingLink({
  controller,
  state,
  hyperlink,
  disabled,
  apply,
  goTo,
}: {
  controller: EditorController;
  state: UiSnapshot;
  hyperlink: { target: string | null; reason: string };
  disabled: boolean;
  apply(target: string | null): Promise<void>;
  goTo(name: string): Promise<void>;
}) {
  const t = messages(state.locale);
  const [target, setTarget] = useState(hyperlink.target ?? "");
  disabled ||= !!hyperlink.reason;
  return (
    <section aria-label={t.objectHyperlink}>
      <form
        onSubmit={(event) => {
          event.preventDefault();
          controller.run(() => apply(target));
        }}
      >
        <fieldset disabled={disabled}>
          <legend>{t.objectHyperlink}</legend>
          <label>
            {t.hyperlinkAddress}
            <input
              type="text"
              inputMode="url"
              maxLength={2048}
              required
              value={target}
              onChange={(event) => setTarget(event.currentTarget.value)}
            />
          </label>
          <p>{t.hyperlinkBookmark}</p>
          <button type="submit">{t.hyperlinkApply}</button>
          <button
            type="button"
            disabled={!hyperlink.target}
            onClick={() => controller.run(() => apply(null))}
          >
            {t.hyperlinkRemove}
          </button>
        </fieldset>
      </form>
      {hyperlink.reason && <p>{hyperlink.reason}</p>}
      {!disabled &&
        hyperlink.target &&
        (hyperlink.target.startsWith("#") ? (
          <button
            type="button"
            onClick={() =>
              controller.run(() => goTo(hyperlink.target!.slice(1)))
            }
          >
            {t.hyperlinkOpen}
          </button>
        ) : (
          <a href={hyperlink.target} target="_blank" rel="noopener noreferrer">
            {t.hyperlinkOpen}
          </a>
        ))}
    </section>
  );
}
