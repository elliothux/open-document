import { useEffect, useState } from "react";
import type { DocumentEditor } from "@open-document/web/editor";
import type {
  FormatValue,
  CharacterFormatPatch,
  ParagraphFormatPatch,
} from "@open-document/web/foundation";
import type { EditorController, UiSnapshot } from "./controller.js";
import { Command, Group } from "./controls.js";
import { messages } from "./messages.js";

interface Props {
  controller: EditorController;
  state: UiSnapshot;
  editor: DocumentEditor;
  disabled: boolean;
}

function NumericFormat({
  label,
  value,
  min,
  max,
  step,
  apply,
  mixed,
  onApply,
  disabled,
}: {
  label: string;
  value: FormatValue<number> | undefined;
  min: number;
  max: number;
  step: number;
  apply: string;
  mixed: string;
  disabled: boolean;
  onApply: (value: number) => void;
}) {
  const current = value?.kind === "value" ? String(value.value) : "";
  const [draft, setDraft] = useState(current);
  useEffect(() => setDraft(current), [current]);
  return (
    <form
      onSubmit={(event) => {
        event.preventDefault();
        if (draft !== "") onApply(Number(draft));
      }}
    >
      <label>
        {label}
        <input
          type="number"
          value={draft}
          min={min}
          max={max}
          step={step}
          disabled={disabled}
          placeholder={value?.kind === "mixed" ? mixed : ""}
          onChange={(event) => setDraft(event.currentTarget.value)}
        />
      </label>
      <button
        type="submit"
        aria-label={`${apply} ${label}`}
        disabled={disabled || draft === ""}
      >
        {apply}
      </button>
    </form>
  );
}

export function DocxFormatCommands({
  controller,
  state,
  editor,
  disabled,
}: Props) {
  const t = messages(state.locale),
    formatting = editor.getSnapshot().data.formatting;
  const character = formatting?.character;
  disabled ||= !formatting || !!formatting.reason;
  const set = (format: CharacterFormatPatch) =>
    controller.run(() => editor.setCharacterFormat(format));
  const paragraph = (format: ParagraphFormatPatch) =>
    controller.run(() => editor.setParagraphFormat(format));
  const family =
    character?.family.kind === "value" ? character.family.value : "";
  const families = [
    ...new Set([
      family,
      ...Object.keys(controller.options.resources.profile).filter(
        (key) => !key.includes("|"),
      ),
    ]),
  ].filter(Boolean);
  const currentColor =
    character?.color.kind === "value" && character.color.value !== "auto"
      ? character.color.value
      : "000000";
  const [color, setColor] = useState(currentColor);
  useEffect(() => setColor(currentColor), [currentColor]);
  const align = formatting?.paragraph.align;
  return (
    <>
      <Group label={t.font}>
        <label>
          {t.fontFamily}
          <select
            aria-label={t.fontFamily}
            value={family}
            disabled={disabled}
            onChange={(event) => set({ family: event.currentTarget.value })}
          >
            <option value="" disabled>
              {t.mixed}
            </option>
            {families.map((name) => (
              <option key={name}>{name}</option>
            ))}
          </select>
        </label>
        <NumericFormat
          label={t.fontSize}
          value={character?.size}
          min={0.5}
          max={1024}
          step={0.5}
          disabled={disabled}
          apply={t.apply}
          mixed={t.mixed}
          onApply={(size) => set({ size })}
        />
        {(["bold", "italic"] as const).map((key) => {
          const value = character?.[key];
          return (
            <button
              key={key}
              type="button"
              disabled={disabled}
              aria-pressed={
                value?.kind === "mixed"
                  ? "mixed"
                  : value?.kind === "value" && value.value
              }
              onClick={() =>
                set({ [key]: !(value?.kind === "value" && value.value) })
              }
            >
              {t[key]}
            </button>
          );
        })}
        <label>
          {t.textColor}
          {character?.color.kind === "mixed" && <span>{t.mixed}</span>}
          <input
            type="color"
            aria-label={t.textColor}
            aria-description={
              character?.color.kind === "mixed" ? t.mixed : undefined
            }
            value={`#${color}`}
            disabled={disabled}
            onChange={(event) => setColor(event.currentTarget.value.slice(1))}
          />
        </label>
        <Command
          label={t.applyColor}
          disabled={disabled}
          action={() => set({ color })}
        />
        <Command
          label={t.clearFont}
          disabled={disabled}
          action={() =>
            set({
              family: null,
              size: null,
              color: null,
              bold: null,
              italic: null,
            })
          }
        />
      </Group>
      <Group label={t.paragraph}>
        {(["left", "center", "right"] as const).map((value) => (
          <button
            key={value}
            type="button"
            disabled={disabled}
            aria-pressed={
              align?.kind === "mixed"
                ? "mixed"
                : align?.kind === "value" && align.value === value
            }
            onClick={() => paragraph({ align: value })}
          >
            {
              t[
                value === "left"
                  ? "alignLeft"
                  : value === "center"
                    ? "alignCenter"
                    : "alignRight"
              ]
            }
          </button>
        ))}
        <Command
          label={t.clearParagraph}
          disabled={disabled}
          action={() =>
            paragraph({
              align: null,
              before: null,
              after: null,
              left: null,
              right: null,
              first: null,
              pageBreakBefore: null,
            })
          }
        />
      </Group>
    </>
  );
}

export function DocxProperties({ controller, state, editor, disabled }: Props) {
  const t = messages(state.locale),
    formatting = editor.getSnapshot().data.formatting;
  disabled ||= !formatting || !!formatting.reason;
  return (
    <aside className="od-properties" aria-label={t.paragraph}>
      <h2>{t.paragraph}</h2>
      <p>{formatting?.reason}</p>
      {(["before", "after", "left", "right", "first"] as const).map((key) => (
        <NumericFormat
          key={key}
          label={
            t[
              key === "before"
                ? "spaceBefore"
                : key === "after"
                  ? "spaceAfter"
                  : key === "left"
                    ? "indentLeft"
                    : key === "right"
                      ? "indentRight"
                      : "firstIndent"
            ]
          }
          value={formatting?.paragraph[key]}
          min={key === "first" ? -1584 : 0}
          max={1584}
          step={0.05}
          disabled={disabled}
          apply={t.apply}
          mixed={t.mixed}
          onApply={(value) =>
            controller.run(() => editor.setParagraphFormat({ [key]: value }))
          }
        />
      ))}
      <label>
        <input
          type="checkbox"
          ref={(node) => {
            if (node)
              node.indeterminate =
                formatting?.paragraph.pageBreakBefore.kind === "mixed";
          }}
          disabled={disabled}
          checked={
            formatting?.paragraph.pageBreakBefore.kind === "value" &&
            formatting.paragraph.pageBreakBefore.value
          }
          onChange={(event) =>
            controller.run(() =>
              editor.setParagraphFormat({
                pageBreakBefore: event.currentTarget.checked,
              }),
            )
          }
        />
        {t.pageBreakBefore}
      </label>
    </aside>
  );
}
