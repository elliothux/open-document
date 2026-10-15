import { useEffect, useState } from "react";
import type { DocumentEditor } from "@open-document/web/editor";
import type { TabStop } from "@open-document/web/foundation";
import type { EditorController, UiSnapshot } from "./controller.js";
import { messages } from "./messages.js";

export function DocxTabs({
  controller,
  state,
  editor,
  disabled,
}: {
  controller: EditorController;
  state: UiSnapshot;
  editor: DocumentEditor;
  disabled: boolean;
}) {
  const t = messages(state.locale);
  const current = editor.getSnapshot().data.formatting?.paragraph.tabs;
  const value = current?.kind === "value" ? current.value : undefined;
  const [draft, setDraft] = useState<TabStop[]>(value ?? []);
  useEffect(() => setDraft(value ?? []), [value]);
  const update = (index: number, change: Partial<TabStop>) =>
    setDraft(
      draft.map((stop, i) => (i === index ? { ...stop, ...change } : stop)),
    );
  return (
    <form
      onSubmit={(event) => {
        event.preventDefault();
        controller.run(() =>
          editor.setParagraphFormat({
            tabs: [...draft].sort((a, b) => a.position - b.position),
          }),
        );
      }}
    >
      <fieldset disabled={disabled}>
        <legend>{t.tabStops}</legend>
        {current?.kind === "mixed" && <p>{t.mixed}</p>}
        {draft.map((stop, index) => (
          <div key={index}>
            <label>
              {t.tabPosition}
              <input
                type="number"
                aria-label={`${t.tabPosition} ${index + 1}`}
                required
                min={0}
                max={1584}
                step={0.05}
                value={Number.isFinite(stop.position) ? stop.position : ""}
                onChange={(event) =>
                  update(index, { position: event.currentTarget.valueAsNumber })
                }
              />
            </label>
            <label>
              {t.tabAlignment}
              <select
                aria-label={`${t.tabAlignment} ${index + 1}`}
                value={stop.align}
                onChange={(event) => {
                  const align = (
                    ["left", "center", "right", "decimal", "bar"] as const
                  ).find((value) => value === event.currentTarget.value);
                  if (align)
                    update(index, {
                      align,
                      ...(align === "bar" ? { leader: "none" } : {}),
                    });
                }}
              >
                <option value="left">{t.alignLeft}</option>
                <option value="center">{t.alignCenter}</option>
                <option value="right">{t.alignRight}</option>
                <option value="decimal">{t.tabDecimal}</option>
                <option value="bar">{t.tabBar}</option>
              </select>
            </label>
            <label>
              {t.tabLeader}
              <select
                aria-label={`${t.tabLeader} ${index + 1}`}
                disabled={stop.align === "bar"}
                value={stop.leader ?? "none"}
                onChange={(event) => {
                  const leader = (
                    [
                      "none",
                      "dot",
                      "hyphen",
                      "underscore",
                      "heavy",
                      "middleDot",
                    ] as const
                  ).find((value) => value === event.currentTarget.value);
                  if (leader) update(index, { leader });
                }}
              >
                <option value="none">{t.tabLeaderNone}</option>
                <option value="dot">{t.tabLeaderDot}</option>
                <option value="hyphen">{t.tabLeaderHyphen}</option>
                <option value="underscore">{t.tabLeaderUnderscore}</option>
                <option value="heavy">{t.tabLeaderHeavy}</option>
                <option value="middleDot">{t.tabLeaderMiddleDot}</option>
              </select>
            </label>
            <button
              type="button"
              aria-label={`${t.removeTabStop} ${index + 1}`}
              onClick={() => setDraft(draft.filter((_, i) => i !== index))}
            >
              {t.removeTabStop}
            </button>
          </div>
        ))}
        <button
          type="button"
          disabled={
            draft.length >= 64 ||
            draft.some(
              (stop) =>
                !Number.isFinite(stop.position) || stop.position >= 1584,
            )
          }
          onClick={() =>
            setDraft([
              ...draft,
              {
                position: Math.min(
                  1584,
                  Math.max(0, ...draft.map((stop) => stop.position)) + 36,
                ),
                align: "left",
              },
            ])
          }
        >
          {t.addTabStop}
        </button>
        <button type="submit">{t.applyTabStops}</button>
        <button
          type="button"
          onClick={() =>
            controller.run(() => editor.setParagraphFormat({ tabs: [] }))
          }
        >
          {t.clearTabStops}
        </button>
        <button
          type="button"
          onClick={() =>
            controller.run(() => editor.setParagraphFormat({ tabs: null }))
          }
        >
          {t.restoreTabStops}
        </button>
      </fieldset>
    </form>
  );
}
