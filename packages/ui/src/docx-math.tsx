import { useState } from "react";
import type {
  DocumentEditor,
  DocumentMathFractions,
} from "@open-document/web/editor";
import type { DocxFractionValue } from "@open-document/web/foundation";
import type { EditorController, UiSnapshot } from "./controller.js";
import { messages } from "./messages.js";

export function DocxMath({
  controller,
  state,
  editor,
  disabled,
  insertDisabled,
}: {
  controller: EditorController;
  state: UiSnapshot;
  editor: DocumentEditor;
  disabled: boolean;
  insertDisabled: boolean;
}) {
  const t = messages(state.locale);
  const [catalog, setCatalog] = useState<DocumentMathFractions>();
  const [id, setId] = useState<number>();
  const [draft, setDraft] = useState<DocxFractionValue>({
    numerator: "1",
    denominator: "2",
  });
  const current = catalog?.items.find((item) => item.id === id);
  const stale = catalog?.revision !== editor.getSnapshot().revision;
  const load = async () => {
    const value = await editor.mathFractions();
    setCatalog(value);
    const item = value.items.find((item) => item.id === id) ?? value.items[0];
    setId(item?.id);
    if (item && !item.reason)
      setDraft({ numerator: item.numerator, denominator: item.denominator });
  };
  return (
    <section aria-label={t.mathFractions}>
      <fieldset disabled={disabled}>
        <legend>{t.mathFractions}</legend>
        <button type="button" onClick={() => controller.run(load)}>
          {t.loadFractions}
        </button>
        {catalog && catalog.items.length > 0 && (
          <label>
            {t.chooseFraction}
            <select
              aria-label={t.chooseFraction}
              value={id ?? ""}
              onChange={(event) => {
                const item = catalog.items.find(
                  (item) => item.id === Number(event.currentTarget.value),
                );
                setId(item?.id);
                if (item && !item.reason)
                  setDraft({
                    numerator: item.numerator,
                    denominator: item.denominator,
                  });
              }}
            >
              {catalog.items.map((item) => (
                <option key={item.id} value={item.id}>
                  {item.reason || `${item.numerator}/${item.denominator}`}
                </option>
              ))}
            </select>
          </label>
        )}
        {(["numerator", "denominator"] as const).map((key) => (
          <label key={key}>
            {t[key]}
            <input
              value={draft[key]}
              maxLength={4096}
              required
              onChange={(event) =>
                setDraft({ ...draft, [key]: event.currentTarget.value })
              }
            />
          </label>
        ))}
        <button
          type="button"
          disabled={insertDisabled || !draft.numerator || !draft.denominator}
          onClick={() =>
            controller.run(async () => {
              await editor.insertMathFraction(draft);
              setCatalog(undefined);
              setId(undefined);
              editor.focus();
            })
          }
        >
          {t.insertFraction}
        </button>
        <button
          type="button"
          disabled={
            stale ||
            !current ||
            !!current.reason ||
            !draft.numerator ||
            !draft.denominator
          }
          onClick={() =>
            controller.run(async () => {
              if (!catalog || id === undefined) return;
              await editor.editMathFraction(catalog, id, draft);
              await load();
            })
          }
        >
          {t.applyFraction}
        </button>
        <button
          type="button"
          disabled={stale || !current || !!current.reason}
          onClick={() =>
            controller.run(async () => {
              if (!catalog || id === undefined) return;
              await editor.editMathFraction(catalog, id, null);
              await load();
            })
          }
        >
          {t.deleteFraction}
        </button>
        {current?.reason && <p>{current.reason}</p>}
      </fieldset>
    </section>
  );
}
