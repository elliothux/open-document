import { useState } from "react";
import type { PptxGuide } from "@open-document/web/pptx";
import type { PanelProps } from "./panels.js";
import { messages } from "./messages.js";

export function PptxGuides({ controller, state, file, disabled }: PanelProps) {
  const query = file.format === "pptx" ? file.editor.query : undefined,
    t = messages(state.locale);
  const [visible, setVisible] = useState(query?.guides.visible ?? false),
    [items, setItems] = useState<PptxGuide[]>(query?.guides.items ?? []);
  if (file.format !== "pptx" || !query) return null;
  const editor = file.editor,
    add = (orientation: PptxGuide["orientation"]) => {
      const previous = items.filter((item) => item.orientation === orientation),
        size = orientation === "horz" ? query.height : query.width,
        position = previous.length
          ? Math.min(
              size,
              Math.max(...previous.map((item) => item.position)) + 12.5,
            )
          : size / 2;
      setItems([...items, { orientation, position }]);
      setVisible(true);
    };
  return (
    <form
      onSubmit={(event) => {
        event.preventDefault();
        controller.run(() =>
          editor.editSlides({ action: "guides", visible, items }),
        );
      }}
    >
      <fieldset disabled={disabled || !!query.guides.reason}>
        <legend>{t.pptxGuides}</legend>
        <label>
          <input
            type="checkbox"
            checked={visible}
            onChange={(event) => setVisible(event.currentTarget.checked)}
          />
          {t.pptxShowGuides}
        </label>
        <p>{t.pptxGuidesHint}</p>
        <button
          type="button"
          disabled={items.length >= 64}
          onClick={() => add("horz")}
        >
          {t.pptxAddHorizontalGuide}
        </button>
        <button
          type="button"
          disabled={items.length >= 64}
          onClick={() => add("vert")}
        >
          {t.pptxAddVerticalGuide}
        </button>
        <ol className="od-guide-list">
          {items.map((item, index) => (
            <li key={index}>
              <label>
                {item.orientation === "horz"
                  ? t.pptxHorizontalGuide
                  : t.pptxVerticalGuide}{" "}
                {index + 1}
                <input
                  type="number"
                  required
                  step={0.125}
                  min={-268435456}
                  max={268435455.875}
                  aria-label={`${t.pptxGuidePosition} ${index + 1}`}
                  value={item.position}
                  onChange={(event) =>
                    setItems(
                      items.map((guide, i) =>
                        i === index
                          ? {
                              ...guide,
                              position: event.currentTarget.valueAsNumber,
                            }
                          : guide,
                      ),
                    )
                  }
                />
              </label>
              <button
                type="button"
                aria-label={`${t.pptxRemoveGuide} ${index + 1}`}
                onClick={() => setItems(items.filter((_, i) => i !== index))}
              >
                {t.pptxRemoveGuide}
              </button>
            </li>
          ))}
        </ol>
        <button
          type="button"
          disabled={!items.length}
          onClick={() => setItems([])}
        >
          {t.pptxClearGuides}
        </button>
        <button
          type="submit"
          disabled={
            visible === query.guides.visible &&
            JSON.stringify(items) === JSON.stringify(query.guides.items)
          }
        >
          {t.pptxApplyGuides}
        </button>
      </fieldset>
      {query.guides.reason && <p>{query.guides.reason}</p>}
    </form>
  );
}
