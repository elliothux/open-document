import { useRef, useState } from "react";
import type { DocumentEditor } from "@open-document/web/editor";
import type {
  DocxRunningArea,
  DocxRunningKind,
  DocxRunningVariant,
  DocxRunningContent,
} from "@open-document/web/foundation";
import type { EditorController, UiSnapshot } from "./controller.js";
import { messages } from "./messages.js";

function runningDraft(content: DocxRunningContent[]): DocxRunningContent[] {
  const result: DocxRunningContent[] = [{ text: "" }];
  for (const item of content) {
    const last = result.at(-1)!;
    if ("text" in item && "text" in last) last.text += item.text;
    else result.push(item, { text: "" });
  }
  return result;
}

export function DocxRunning({
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
  const [kind, setKind] = useState<DocxRunningKind>("header");
  const [variant, setVariant] = useState<DocxRunningVariant>("default");
  const [first, setFirst] = useState(false);
  const [even, setEven] = useState(false);
  const [area, setArea] = useState<DocxRunningArea>();
  const [content, setContent] = useState<DocxRunningContent[]>([{ text: "" }]);
  const active = useRef<HTMLTextAreaElement | null>(null);
  const [distance, setDistance] = useState(36);
  const stale = area?.revision !== state.document?.revision;
  const load = async () => {
    const value = await editor.runningArea(kind, variant);
    setArea(value);
    setContent(runningDraft(value.content));
    active.current = null;
    setDistance(value.distance);
    setFirst(value.differentFirst);
    setEven(value.differentEven);
  };
  const insertField = (field: "PAGE" | "NUMPAGES") => {
    const input = active.current;
    const index = input ? Number(input.dataset.index) : content.length - 1;
    const item = content[index];
    if (!item || !("text" in item)) return;
    const start = input?.selectionStart ?? item.text.length;
    const end = input?.selectionEnd ?? start;
    setContent([
      ...content.slice(0, index),
      { text: item.text.slice(0, start) },
      { field },
      { text: item.text.slice(end) },
      ...content.slice(index + 1),
    ]);
    active.current = null;
  };
  return (
    <section aria-label={t.runningArea}>
      <h3>{t.runningArea}</h3>
      <label>
        {t.runningArea}
        <select
          disabled={disabled}
          value={kind}
          onChange={(event) => {
            setKind(
              event.currentTarget.value === "footer" ? "footer" : "header",
            );
            setArea(undefined);
          }}
        >
          <option value="header">{t.header}</option>
          <option value="footer">{t.footer}</option>
        </select>
      </label>
      <label>
        {t.runningVariant}
        <select
          disabled={disabled}
          value={variant}
          onChange={(event) => {
            const value = event.currentTarget.value;
            setVariant(
              value === "first" || value === "even" ? value : "default",
            );
            setArea(undefined);
          }}
        >
          <option value="default">{t.runningDefault}</option>
          <option value="first">
            {kind === "header" ? t.firstHeader : t.firstFooter}
          </option>
          <option value="even">
            {kind === "header" ? t.evenHeader : t.evenFooter}
          </option>
        </select>
      </label>
      <button
        type="button"
        disabled={disabled}
        onClick={() => controller.run(load)}
      >
        {t.loadRunningArea}
      </button>
      {area && (
        <button
          type="button"
          disabled={disabled || stale || !area.shared}
          onClick={() =>
            controller.run(async () => {
              await editor.unlinkRunningArea(kind, variant);
              await load();
            })
          }
        >
          {t.unlinkRunningArea}
        </button>
      )}
      {area && (
        <form
          onSubmit={(event) => {
            event.preventDefault();
            controller.run(async () => {
              await editor.setRunningArea(kind, variant, content, distance);
              await load();
            });
          }}
        >
          <fieldset disabled={disabled || stale || !!area.reason}>
            <label>
              <input
                type="checkbox"
                checked={first}
                onChange={(event) => setFirst(event.currentTarget.checked)}
              />
              {t.headerDifferentFirst}
            </label>
            <label>
              <input
                type="checkbox"
                checked={even}
                onChange={(event) => setEven(event.currentTarget.checked)}
              />
              {t.headerDifferentOddEven}
            </label>
            <button
              type="button"
              onClick={() =>
                controller.run(async () => {
                  await editor.setRunningOptions(first, even);
                  const value = await editor.runningArea(kind, variant);
                  setArea(value);
                  setFirst(value.differentFirst);
                  setEven(value.differentEven);
                })
              }
            >
              {t.applyRunningOptions}
            </button>
            {content.map((item, index) =>
              "text" in item ? (
                <label key={index}>
                  {kind === "header" ? t.header : t.footer}
                  <textarea
                    data-index={index}
                    maxLength={8192}
                    value={item.text}
                    onFocus={(event) => {
                      active.current = event.currentTarget;
                    }}
                    onChange={(event) => {
                      const text = event.currentTarget.value;
                      setContent(
                        content.map((part, i) =>
                          i === index ? { text } : part,
                        ),
                      );
                    }}
                  />
                </label>
              ) : (
                <div key={index}>
                  <label>
                    {t.runningField}
                    <select
                      value={item.field}
                      onChange={(event) => {
                        const field =
                          event.currentTarget.value === "PAGE"
                            ? "PAGE"
                            : "NUMPAGES";
                        setContent(
                          content.map((part, i) =>
                            i === index ? { field } : part,
                          ),
                        );
                      }}
                    >
                      <option value="PAGE">{t.currentPageField}</option>
                      <option value="NUMPAGES">{t.totalPagesField}</option>
                    </select>
                  </label>
                  <button
                    type="button"
                    onClick={() => {
                      setContent(
                        runningDraft(content.filter((_, i) => i !== index)),
                      );
                      active.current = null;
                    }}
                  >
                    {t.removeRunningField}
                  </button>
                </div>
              ),
            )}
            <button type="button" onClick={() => insertField("PAGE")}>
              {t.insertCurrentPageField}
            </button>
            <button type="button" onClick={() => insertField("NUMPAGES")}>
              {t.insertTotalPagesField}
            </button>
            <label>
              {kind === "header" ? t.headerDistance : t.footerDistance}
              <input
                type="number"
                min={0}
                max={14400}
                step={0.05}
                required
                value={Number.isFinite(distance) ? distance : ""}
                onChange={(event) =>
                  setDistance(event.currentTarget.valueAsNumber)
                }
              />
            </label>
            <button type="submit">{t.apply}</button>
          </fieldset>
          {area.reason && <p>{area.reason}</p>}
          {stale && <p>{t.reloadPageSetup}</p>}
        </form>
      )}
    </section>
  );
}
