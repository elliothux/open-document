import type { TabStop } from "../web/foundation.js";
import type { UiSnapshot } from "./context.js";
import { messages } from "@open-document/ui/messages";

export function DocxTabFields({
  draft,
  setDraft,
  locale,
  prefix = "",
}: {
  draft: TabStop[];
  setDraft: (draft: TabStop[]) => void;
  locale: UiSnapshot["locale"];
  prefix?: string;
}) {
  const t = messages(locale);
  const update = (index: number, change: Partial<TabStop>) =>
    setDraft(
      draft.map((stop, i) => (i === index ? { ...stop, ...change } : stop)),
    );
  return (
    <>
      {draft.map((stop, index) => (
        <div key={index}>
          <label>
            {t.tabPosition}
            <input
              type="number"
              aria-label={`${prefix}${t.tabPosition} ${index + 1}`}
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
              aria-label={`${prefix}${t.tabAlignment} ${index + 1}`}
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
              aria-label={`${prefix}${t.tabLeader} ${index + 1}`}
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
            aria-label={`${prefix}${t.removeTabStop} ${index + 1}`}
            onClick={() => setDraft(draft.filter((_, i) => i !== index))}
          >
            {t.removeTabStop}
          </button>
        </div>
      ))}
      <button
        type="button"
        aria-label={`${prefix}${t.addTabStop}`}
        disabled={
          draft.length >= 64 ||
          draft.some(
            (stop) => !Number.isFinite(stop.position) || stop.position >= 1584,
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
    </>
  );
}
