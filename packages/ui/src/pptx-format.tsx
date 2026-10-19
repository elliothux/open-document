import { useState } from "react";
import type { PresentationEditor } from "@open-document/web/presentation-editor";
import type {
  PptxTextFormat,
  PptxTextSpacing,
  PptxParagraphFormat,
  PptxListFormat,
  PptxParagraphTab,
} from "@open-document/web/pptx";
import type { EditorController, UiSnapshot } from "./controller.js";
import { messages } from "./messages.js";

export function TextField({
  property,
  label,
  value,
  mixed,
  apply,
  disabled,
  onApply,
}: {
  property: "font" | "size" | "color" | "highlight";
  label: string;
  value: string | number | null;
  mixed: string;
  apply: string;
  disabled: boolean;
  onApply: (format: PptxTextFormat) => void;
}) {
  const [draft, setDraft] = useState(value === null ? "" : String(value));
  return (
    <form
      onSubmit={(event) => {
        event.preventDefault();
        onApply(
          property === "size" ? { size: Number(draft) } : { [property]: draft },
        );
      }}
    >
      <label>
        {label}
        <input
          aria-label={label}
          required
          value={draft}
          type={property === "size" ? "number" : "text"}
          min={property === "size" ? 1 : undefined}
          max={property === "size" ? 1024 : undefined}
          step={property === "size" ? "0.01" : undefined}
          maxLength={
            property === "font"
              ? 200
              : property === "color" || property === "highlight"
                ? 6
                : undefined
          }
          pattern={
            property === "color" || property === "highlight"
              ? "[0-9a-fA-F]{6}"
              : undefined
          }
          placeholder={value === null ? mixed : ""}
          onChange={(event) => setDraft(event.currentTarget.value)}
        />
      </label>
      <button type="submit" disabled={disabled || !draft}>
        {apply} {label}
      </button>
    </form>
  );
}

export function ParagraphField({
  property,
  label,
  value,
  state,
  disabled,
  onApply,
}: {
  property:
    | "left"
    | "right"
    | "first"
    | "before"
    | "after"
    | "line"
    | "listSize"
    | "defaultTab";
  label: string;
  value: number | PptxTextSpacing | null;
  state: UiSnapshot;
  disabled: boolean;
  onApply: (format: PptxParagraphFormat) => void;
}) {
  const t = messages(state.locale),
    spacing =
      property === "before" ||
      property === "after" ||
      property === "line" ||
      property === "listSize";
  const [draft, setDraft] = useState(
    value === null
      ? ""
      : String(typeof value === "number" ? value : value.value),
  );
  const [unit, setUnit] = useState<PptxTextSpacing["unit"]>(
    value !== null && typeof value !== "number"
      ? value.unit
      : property === "line"
        ? "percent"
        : "point",
  );
  return (
    <form
      onSubmit={(event) => {
        event.preventDefault();
        onApply(
          spacing
            ? { [property]: { unit, value: Number(draft) } }
            : { [property]: Number(draft) },
        );
      }}
    >
      <label>
        {label}
        <input
          aria-label={label}
          type="number"
          required
          value={draft}
          placeholder={value === null ? t.mixed : ""}
          min={
            property === "listSize"
              ? 1
              : property === "first"
                ? -4032
                : property === "line"
                  ? unit === "point"
                    ? 0.01
                    : 0.001
                  : 0
          }
          max={
            property === "listSize"
              ? unit === "point"
                ? 1024
                : 400
              : spacing
                ? unit === "point"
                  ? 1584
                  : 1000
                : property === "defaultTab"
                  ? 1584
                  : 4032
          }
          step={spacing ? (unit === "point" ? 0.01 : 0.001) : "any"}
          onChange={(event) => setDraft(event.currentTarget.value)}
        />
      </label>
      {spacing && (
        <label>
          {t.spacingUnit}
          <select
            aria-label={`${label} ${t.spacingUnit}`}
            value={unit}
            onChange={(event) => {
              const value = event.currentTarget.value;
              if (value === "point" || value === "percent") setUnit(value);
            }}
          >
            <option value="point">{t.pointUnit}</option>
            <option value="percent">{t.percentUnit}</option>
          </select>
        </label>
      )}
      <button type="submit" disabled={disabled || !draft}>
        {t.apply} {label}
      </button>
    </form>
  );
}

export function PptxParagraph({
  controller,
  state,
  editor,
  disabled,
}: {
  controller: EditorController;
  state: UiSnapshot;
  editor: PresentationEditor;
  disabled: boolean;
}) {
  const t = messages(state.locale),
    paragraph = editor.query.paragraph;
  return (
    <fieldset
      disabled={
        !!paragraph.reason ||
        state.loading ||
        state.saving ||
        !!state.document?.composition ||
        !!state.document?.paused ||
        !!state.document?.dragging ||
        !!state.document?.closed
      }
    >
      <legend>{t.paragraph}</legend>
      <label>
        <input
          type="checkbox"
          checked={paragraph.rtl === true}
          ref={(input) => {
            if (input) input.indeterminate = paragraph.rtl === null;
          }}
          disabled={disabled}
          onChange={(event) => {
            const rtl = event.currentTarget.checked;
            controller.run(() =>
              editor.editObjects({ action: "textParagraph", format: { rtl } }),
            );
          }}
        />
        {t.paragraphRtl}
      </label>
      {(
        [
          ["left", t.indentLeft],
          ["right", t.indentRight],
          ["first", t.firstIndent],
          ["before", t.paragraphBefore],
          ["after", t.paragraphAfter],
          ["line", t.lineSpacing],
        ] as const
      ).map(([key, label]) => (
        <ParagraphField
          key={`${key}:${JSON.stringify(paragraph[key])}`}
          property={key}
          label={label}
          value={paragraph[key]}
          state={state}
          disabled={disabled}
          onApply={(format) =>
            controller.run(() =>
              editor.editObjects({ action: "textParagraph", format }),
            )
          }
        />
      ))}
      <PptxTabs
        key={`tabs:${JSON.stringify(paragraph.tabs)}:${paragraph.defaultTab}`}
        state={state}
        tabs={paragraph.tabs}
        defaultTab={paragraph.defaultTab}
        disabled={disabled}
        apply={(format) =>
          controller.run(() =>
            editor.editObjects({ action: "textParagraph", format }),
          )
        }
      />
      <PptxListFields
        key={`list:${JSON.stringify(paragraph.list)}:${paragraph.level}`}
        state={state}
        disabled={disabled}
        list={paragraph.list}
        level={paragraph.level}
        onApply={(format) =>
          controller.run(() =>
            editor.editObjects({ action: "textParagraph", format }),
          )
        }
      />
      {(
        [
          ["font", "listFont", t.listFont],
          ["color", "listColor", t.listColor],
        ] as const
      ).map(([property, field, label]) => (
        <TextField
          key={`${field}:${paragraph[field]}`}
          property={property}
          label={label}
          value={paragraph[field]}
          mixed={t.mixed}
          apply={t.apply}
          disabled={disabled}
          onApply={(format) =>
            controller.run(() =>
              editor.editObjects({
                action: "textParagraph",
                format: { [field]: format[property] },
              }),
            )
          }
        />
      ))}
      <ParagraphField
        key={`listSize:${JSON.stringify(paragraph.listSize)}`}
        property="listSize"
        label={t.listSize}
        value={paragraph.listSize}
        state={state}
        disabled={disabled}
        onApply={(format) =>
          controller.run(() =>
            editor.editObjects({ action: "textParagraph", format }),
          )
        }
      />
      <button
        type="button"
        disabled={disabled}
        onClick={() =>
          controller.run(() =>
            editor.editObjects({
              action: "textParagraph",
              format: { listFont: null, listSize: null, listColor: null },
            }),
          )
        }
      >
        {t.listTextStyle}
      </button>
      <button
        type="button"
        disabled={disabled}
        onClick={() =>
          controller.run(() =>
            editor.editObjects({ action: "clearParagraphFormat" }),
          )
        }
      >
        {t.clearParagraph}
      </button>
      {paragraph.reason && <p>{paragraph.reason}</p>}
    </fieldset>
  );
}

export function PptxTabs({
  state,
  tabs,
  defaultTab,
  disabled,
  apply,
}: {
  state: UiSnapshot;
  tabs: PptxParagraphTab[] | null;
  defaultTab: number | null;
  disabled: boolean;
  apply: (format: PptxParagraphFormat) => void;
}) {
  const t = messages(state.locale);
  const [draft, setDraft] = useState<PptxParagraphTab[]>(tabs ?? []);
  const update = (index: number, change: Partial<PptxParagraphTab>) =>
    setDraft(
      draft.map((tab, i) => (i === index ? { ...tab, ...change } : tab)),
    );
  return (
    <>
      <ParagraphField
        property="defaultTab"
        label={t.defaultTabInterval}
        value={defaultTab}
        state={state}
        disabled={disabled}
        onApply={apply}
      />
      <button
        type="button"
        disabled={disabled}
        onClick={() => apply({ defaultTab: null })}
      >
        {t.restoreDefaultTab}
      </button>
      <form
        onSubmit={(event) => {
          event.preventDefault();
          apply({ tabs: [...draft].sort((a, b) => a.position - b.position) });
        }}
      >
        <fieldset disabled={disabled}>
          <legend>{t.tabStops}</legend>
          {tabs === null && <p>{t.mixed}</p>}
          {draft.map((tab, index) => (
            <div key={index}>
              <label>
                {t.tabPosition}
                <input
                  aria-label={`${t.tabPosition} ${index + 1}`}
                  type="number"
                  required
                  min={0}
                  max={1584}
                  step={0.05}
                  value={Number.isFinite(tab.position) ? tab.position : ""}
                  onChange={(event) =>
                    update(index, {
                      position: event.currentTarget.valueAsNumber,
                    })
                  }
                />
              </label>
              <label>
                {t.tabAlignment}
                <select
                  aria-label={`${t.tabAlignment} ${index + 1}`}
                  value={tab.align}
                  onChange={(event) => {
                    const align = (
                      ["left", "center", "right", "decimal"] as const
                    ).find((value) => value === event.currentTarget.value);
                    if (align) update(index, { align });
                  }}
                >
                  <option value="left">{t.alignLeft}</option>
                  <option value="center">{t.alignCenter}</option>
                  <option value="right">{t.alignRight}</option>
                  <option value="decimal">{t.tabDecimal}</option>
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
              draft.length >= 32 ||
              draft.some(
                (tab) => !Number.isFinite(tab.position) || tab.position >= 1584,
              )
            }
            onClick={() =>
              setDraft([
                ...draft,
                {
                  position: Math.min(
                    1584,
                    Math.max(0, ...draft.map((tab) => tab.position)) + 36,
                  ),
                  align: "left",
                },
              ])
            }
          >
            {t.addTabStop}
          </button>
          <button type="submit">{t.applyTabStops}</button>
          <button type="button" onClick={() => apply({ tabs: [] })}>
            {t.clearTabStops}
          </button>
          <button type="button" onClick={() => apply({ tabs: null })}>
            {t.restoreTabStops}
          </button>
        </fieldset>
      </form>
    </>
  );
}

export function PptxListFields({
  state,
  disabled,
  list,
  level,
  onApply,
}: {
  state: UiSnapshot;
  disabled: boolean;
  list: PptxListFormat | null;
  level?: number | null;
  onApply: (format: PptxParagraphFormat) => void;
}) {
  const t = messages(state.locale);
  const [kind, setKind] = useState(list?.kind ?? "bullet");
  const [symbol, setSymbol] = useState(
    list?.kind === "bullet" ? list.value : "•",
  );
  const [number, setNumber] = useState<
    Extract<PptxListFormat, { kind: "number" }>["value"]
  >(list?.kind === "number" ? list.value : "arabicPeriod");
  const [start, setStart] = useState(list?.kind === "number" ? list.start : 1);
  const [draftLevel, setLevel] = useState(
    level == null ? "" : String(level + 1),
  );
  const numberStyles = [
    ["arabicPeriod", t.listFormat_decimal],
    ["arabicParenBoth", "(1) (2) (3)"],
    ["arabicParenR", "1) 2) 3)"],
    ["arabicPlain", "1 2 3"],
    ["alphaLcPeriod", t.listFormat_lowerLetter],
    ["alphaLcParenBoth", "(a) (b) (c)"],
    ["alphaLcParenR", "a) b) c)"],
    ["alphaUcPeriod", t.listFormat_upperLetter],
    ["alphaUcParenBoth", "(A) (B) (C)"],
    ["alphaUcParenR", "A) B) C)"],
    ["romanLcPeriod", t.listFormat_lowerRoman],
    ["romanLcParenBoth", "(i) (ii) (iii)"],
    ["romanLcParenR", "i) ii) iii)"],
    ["romanUcPeriod", t.listFormat_upperRoman],
    ["romanUcParenBoth", "(I) (II) (III)"],
    ["romanUcParenR", "I) II) III)"],
  ] as const;
  return (
    <form
      onSubmit={(event) => {
        event.preventDefault();
        onApply({
          list:
            kind === "number"
              ? { kind, value: number, start }
              : kind === "bullet"
                ? { kind, value: symbol }
                : { kind: "none" },
        });
      }}
    >
      <label>
        {t.listFormat}
        <select
          aria-label={t.listFormat}
          value={kind}
          onChange={(event) => {
            const kind = event.currentTarget.value;
            if (kind === "none" || kind === "bullet" || kind === "number")
              setKind(kind);
          }}
        >
          <option value="none">{t.removeList}</option>
          <option value="bullet">{t.listFormat_bullet}</option>
          <option value="number">{t.listFormat_decimal}</option>
        </select>
      </label>
      {kind === "bullet" && (
        <label>
          {t.listSymbol}
          <input
            aria-label={t.listSymbol}
            required
            maxLength={16}
            value={symbol}
            onChange={(event) => setSymbol(event.currentTarget.value)}
          />
        </label>
      )}
      {kind === "number" && (
        <>
          <label>
            {t.numberingFormat}
            <select
              aria-label={t.numberingFormat}
              value={number}
              onChange={(event) => {
                const value = numberStyles.find(
                  ([key]) => key === event.currentTarget.value,
                )?.[0];
                if (value) setNumber(value);
              }}
            >
              {numberStyles.map(([value, label]) => (
                <option key={value} value={value}>
                  {label}
                </option>
              ))}
            </select>
          </label>
          <label>
            {t.listStart}
            <input
              aria-label={t.listStart}
              type="number"
              min={1}
              max={32767}
              required
              value={start}
              onChange={(event) => setStart(Number(event.currentTarget.value))}
            />
          </label>
        </>
      )}
      <button type="submit" disabled={disabled}>
        {t.applyList}
      </button>
      {level !== undefined && (
        <>
          <label>
            {t.listLevel}
            <input
              aria-label={t.listLevel}
              type="number"
              min={1}
              max={9}
              placeholder={level === null ? t.mixed : ""}
              value={draftLevel}
              onChange={(event) => setLevel(event.currentTarget.value)}
            />
          </label>
          <button
            type="button"
            disabled={disabled || !draftLevel}
            onClick={() => onApply({ level: Number(draftLevel) - 1 })}
          >
            {t.updateListLevel}
          </button>
        </>
      )}
    </form>
  );
}

export function PptxFormat({
  controller,
  state,
  editor,
  disabled,
}: {
  controller: EditorController;
  state: UiSnapshot;
  editor: PresentationEditor;
  disabled: boolean;
}) {
  const t = messages(state.locale),
    format = editor.query.formatting;
  const apply = (format: PptxTextFormat) =>
    controller.run(() => editor.editObjects({ action: "textFormat", format }));
  return (
    <fieldset
      disabled={
        !!format.reason ||
        state.loading ||
        state.saving ||
        !!state.document?.composition ||
        !!state.document?.paused ||
        !!state.document?.dragging ||
        !!state.document?.closed
      }
    >
      <legend>{t.textFormat}</legend>
      {(
        [
          ["font", t.fontFamily],
          ["size", t.fontSize],
          ["color", t.textColor],
          ["highlight", t.highlightColor],
        ] as const
      ).map(([key, label]) => (
        <TextField
          key={`${key}:${format[key]}`}
          property={key}
          label={label}
          value={format[key]}
          mixed={t.mixed}
          apply={t.apply}
          disabled={disabled}
          onApply={apply}
        />
      ))}
      {(
        [
          ["bold", t.bold],
          ["italic", t.italic],
          ["underline", t.underline],
          ["strike", t.strike],
        ] as const
      ).map(([key, label]) => (
        <button
          key={key}
          type="button"
          disabled={disabled}
          aria-pressed={format[key] === null ? "mixed" : format[key]}
          onClick={() => apply({ [key]: format[key] !== true })}
        >
          {label}
        </button>
      ))}
      {(
        [
          ["left", t.alignLeft],
          ["center", t.alignCenter],
          ["right", t.alignRight],
          ["justify", t.alignJustify],
        ] as const
      ).map(([alignment, label]) => (
        <button
          key={alignment}
          type="button"
          disabled={disabled}
          aria-pressed={format.alignment === alignment}
          onClick={() =>
            controller.run(() =>
              editor.editObjects({ action: "textAlign", alignment }),
            )
          }
        >
          {label}
        </button>
      ))}
      {(["superscript", "subscript"] as const).map((script) => (
        <button
          key={script}
          type="button"
          disabled={disabled}
          aria-pressed={
            format.script === null ? "mixed" : format.script === script
          }
          onClick={() =>
            apply({ script: format.script === script ? "baseline" : script })
          }
        >
          {t[script]}
        </button>
      ))}
      <button
        type="button"
        disabled={disabled || format.highlight === ""}
        onClick={() => apply({ highlight: "" })}
      >
        {t.highlight_none}
      </button>
      {format.reason && <p>{format.reason}</p>}
      <button
        type="button"
        disabled={disabled}
        onClick={() =>
          controller.run(() =>
            editor.editObjects({ action: "clearTextFormat" }),
          )
        }
      >
        {t.clearFont}
      </button>
    </fieldset>
  );
}
