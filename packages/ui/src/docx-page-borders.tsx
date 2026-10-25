import { useState } from "react";
import type {
  DocxPageBorders,
  DocxPageBorder,
} from "@open-document/web/foundation";
import type { UiSnapshot } from "./controller.js";
import { messages } from "./messages.js";

export function DocxPageBordersForm({
  value,
  reason,
  disabled,
  state,
  apply,
}: {
  value: DocxPageBorders;
  reason: string;
  disabled: boolean;
  state: UiSnapshot;
  apply: (value: DocxPageBorders | null) => void;
}) {
  const t = messages(state.locale);
  const [draft, setDraft] = useState(value);
  const sides: [DocxPageBorder["side"], string][] = [
    ["top", t.pageBorderTop],
    ["left", t.pageBorderLeft],
    ["bottom", t.pageBorderBottom],
    ["right", t.pageBorderRight],
  ];
  return (
    <form
      onSubmit={(event) => {
        event.preventDefault();
        apply(draft);
      }}
    >
      <fieldset disabled={disabled || !!reason}>
        <legend>{t.pageBorders}</legend>
        <label>
          {t.pageBorderOffset}
          <select
            aria-label={t.pageBorderOffset}
            value={draft.offsetFrom}
            onChange={(event) =>
              setDraft({
                ...draft,
                offsetFrom:
                  event.currentTarget.value === "page" ? "page" : "text",
              })
            }
          >
            <option value="page">{t.pageBorderPage}</option>
            <option value="text">{t.pageBorderText}</option>
          </select>
        </label>
        <label>
          {t.pageBorderDisplay}
          <select
            aria-label={t.pageBorderDisplay}
            value={draft.display}
            onChange={(event) => {
              const display = (
                ["allPages", "firstPage", "notFirstPage"] as const
              ).find((value) => value === event.currentTarget.value);
              if (display) setDraft({ ...draft, display });
            }}
          >
            <option value="allPages">{t.pageBorderAll}</option>
            <option value="firstPage">{t.pageBorderFirst}</option>
            <option value="notFirstPage">{t.pageBorderOther}</option>
          </select>
        </label>
        <label>
          {t.pageBorderLayer}
          <select
            aria-label={t.pageBorderLayer}
            value={draft.zOrder}
            onChange={(event) =>
              setDraft({
                ...draft,
                zOrder: event.currentTarget.value === "back" ? "back" : "front",
              })
            }
          >
            <option value="front">{t.pageBorderFront}</option>
            <option value="back">{t.pageBorderBack}</option>
          </select>
        </label>
        {sides.map(([side, label]) => {
          const active = draft.sides.find((border) => border.side === side);
          const border = active ?? {
            side,
            style: "single" as const,
            color: "000000",
            width: 1,
            space: 24,
          };
          const update = (border: DocxPageBorder | undefined) =>
            setDraft({
              ...draft,
              sides: [
                ...draft.sides.filter((item) => item.side !== side),
                ...(border ? [border] : []),
              ],
            });
          return (
            <fieldset key={side}>
              <legend>{label}</legend>
              <label>
                <input
                  type="checkbox"
                  checked={!!active}
                  onChange={(event) =>
                    update(event.currentTarget.checked ? border : undefined)
                  }
                />
                {t.pageBorderEnabled}
              </label>
              <label>
                {t.pageBorderColor}
                <input
                  type="color"
                  disabled={!active}
                  value={`#${border.color}`}
                  onChange={(event) =>
                    update({
                      ...border,
                      color: event.currentTarget.value.slice(1),
                    })
                  }
                />
              </label>
              <label>
                {t.pageBorderStyle}
                <select
                  disabled={!active}
                  value={border.style}
                  onChange={(event) =>
                    update({
                      ...border,
                      style:
                        event.currentTarget.value === "double"
                          ? "double"
                          : "single",
                    })
                  }
                >
                  <option value="single">{t.pageBorderSingle}</option>
                  <option value="double">{t.pageBorderDouble}</option>
                </select>
              </label>
              <label>
                {t.pageBorderWidth}
                <input
                  type="number"
                  disabled={!active}
                  min={0.25}
                  max={12}
                  step={0.125}
                  required
                  value={border.width}
                  onChange={(event) =>
                    update({
                      ...border,
                      width: event.currentTarget.valueAsNumber,
                    })
                  }
                />
              </label>
              <label>
                {t.pageBorderSpace}
                <input
                  type="number"
                  disabled={!active}
                  min={0}
                  max={31}
                  step={1}
                  required
                  value={border.space}
                  onChange={(event) =>
                    update({
                      ...border,
                      space: event.currentTarget.valueAsNumber,
                    })
                  }
                />
              </label>
            </fieldset>
          );
        })}
        <button type="submit">{t.applyPageBorders}</button>
        <button type="button" onClick={() => apply(null)}>
          {t.removePageBorders}
        </button>
      </fieldset>
      {reason && <p>{reason}</p>}
    </form>
  );
}
