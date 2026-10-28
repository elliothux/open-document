import { useRef, useState } from "react";
import type { DocumentEditor } from "../web/editor.js";
import type {
  DocxRunningArea,
  DocxRunningKind,
  DocxRunningVariant,
  DocxRunningContent,
} from "../web/foundation.js";
import type { EditorController, UiSnapshot } from "./context.js";
import { messages } from "@open-document/ui/messages";
import { listFormats } from "../web/foundation.js";

function runningDraft(content: DocxRunningContent[]): DocxRunningContent[] {
  const result: DocxRunningContent[] = [{ text: "" }];
  for (const item of content) {
    const last = result.at(-1)!;
    if ("text" in item && "text" in last && item.target === last.target)
      last.text += item.text;
    else result.push(item, { text: "" });
  }
  return result;
}

export function DocxRunning({
  controller,
  state,
  editor,
  disabled,
  section,
}: {
  controller: EditorController;
  state: UiSnapshot;
  editor: DocumentEditor;
  disabled: boolean;
  section: number;
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
  const stale =
    area?.revision !== state.document?.revision || area?.section !== section;
  const load = async () => {
    const value = await editor.runningArea(section, kind, variant);
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
      start ? { ...item, text: item.text.slice(0, start) } : { text: "" },
      { field },
      end < item.text.length
        ? { ...item, text: item.text.slice(end) }
        : { text: "" },
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
          disabled={disabled || stale || (!area.shared && !area.linked)}
          onClick={() =>
            controller.run(async () => {
              await editor.setRunningLink(section, kind, variant, false);
              await load();
            })
          }
        >
          {t.unlinkRunningArea}
        </button>
      )}
      {area && section > 0 && (
        <button
          type="button"
          disabled={disabled || stale || area.linked}
          onClick={() =>
            controller.run(async () => {
              await editor.setRunningLink(section, kind, variant, true);
              await load();
            })
          }
        >
          {t.linkRunningArea}
        </button>
      )}
      {area && (
        <form
          onSubmit={(event) => {
            event.preventDefault();
            controller.run(async () => {
              await editor.setRunningArea(
                section,
                kind,
                variant,
                content,
                distance,
              );
              await load();
            });
          }}
        >
          <fieldset
            disabled={
              disabled ||
              stale ||
              (!!area.reason && !area.linked && !area.shared)
            }
          >
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
              {t.runningDocumentOddEven}
            </label>
            <button
              type="button"
              onClick={() =>
                controller.run(async () => {
                  await editor.setRunningOptions(section, first, even);
                  const value = await editor.runningArea(
                    section,
                    kind,
                    variant,
                  );
                  setArea(value);
                  setFirst(value.differentFirst);
                  setEven(value.differentEven);
                })
              }
            >
              {t.applyRunningOptions}
            </button>
          </fieldset>
          <fieldset disabled={disabled || stale || !!area.reason}>
            {content.map((item, index) =>
              "text" in item ? (
                <div key={index}>
                  <label>
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
                            i === index
                              ? text
                                ? { ...item, text }
                                : { text }
                              : part,
                          ),
                        );
                      }}
                    />
                  </label>
                  <label>
                    {t.hyperlinkAddress}
                    <input
                      value={item.target ?? ""}
                      maxLength={2048}
                      onChange={(event) => {
                        const target = event.currentTarget.value;
                        setContent(
                          content.map((part, i) =>
                            i === index
                              ? target
                                ? { ...item, target }
                                : { text: item.text }
                              : part,
                          ),
                        );
                      }}
                    />
                  </label>
                </div>
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
                            i === index ? { ...item, field } : part,
                          ),
                        );
                      }}
                    >
                      <option value="PAGE">{t.currentPageField}</option>
                      <option value="NUMPAGES">{t.totalPagesField}</option>
                    </select>
                  </label>
                  <label>
                    {t.fieldNumberFormat}
                    <select
                      value={item.format ?? ""}
                      onChange={(event) => {
                        const format = event.currentTarget.value;
                        setContent(
                          content.map((part, i) =>
                            i === index
                              ? format
                                ? {
                                    field: item.field,
                                    format: format as NonNullable<
                                      typeof item.format
                                    >,
                                  }
                                : { field: item.field }
                              : part,
                          ),
                        );
                      }}
                    >
                      <option value="">{t.inheritedPageNumberFormat}</option>
                      {listFormats
                        .filter(
                          (format) =>
                            format !== "bullet" && format !== "decimalZero",
                        )
                        .map((format) => (
                          <option key={format} value={format}>
                            {t[`listFormat_${format}`]}
                          </option>
                        ))}
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
