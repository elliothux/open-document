import { useEffect, useState } from "react";
import type { DocumentEditor } from "@open-document/web/editor";
import type {
  FormatValue,
  CharacterFormatPatch,
  ParagraphFormatPatch,
  CopiedFormat,
} from "@open-document/web/foundation";
import {
  highlightColors,
  DOCX_PAGE_BREAK,
} from "@open-document/web/foundation";
import type { EditorController, UiSnapshot } from "./controller.js";
import { Command, Group } from "./controls.js";
import { messages } from "./messages.js";
import { DocxSearch } from "./docx-search.js";
import { DocxOverview } from "./docx-overview.js";
import { DocxTabs, DocxDefaultTab } from "./docx-tabs.js";
import { DocxStyles } from "./docx-styles.js";
import { DocxLists } from "./docx-lists.js";
import { DocxPage } from "./docx-page.js";
import { DocxPictures } from "./docx-pictures.js";
import { DocxTables } from "./docx-tables.js";

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
  const [copied, setCopied] = useState<CopiedFormat>();
  useEffect(() => setCopied(undefined), [editor]);
  useEffect(() => setColor(currentColor), [currentColor]);
  const align = formatting?.paragraph.align;
  return (
    <>
      <Group label={t.font}>
        <Command
          label={t.copyFormat}
          disabled={disabled}
          action={() =>
            controller.run(async () => setCopied(await editor.captureFormat()))
          }
        />
        <Command
          label={t.applyFormat}
          disabled={disabled || !copied}
          action={() =>
            controller.run(() =>
              copied ? editor.applyFormat(copied) : Promise.resolve(),
            )
          }
        />
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
        {(["bold", "italic", "underline", "strike"] as const).map((key) => {
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
              underline: null,
              strike: null,
              highlight: null,
              vertAlign: null,
            })
          }
        />
      </Group>
      <Group label={t.textEffects}>
        <label>
          {t.highlightColor}
          <select
            aria-label={t.highlightColor}
            disabled={disabled}
            value={
              character?.highlight.kind === "value"
                ? character.highlight.value
                : ""
            }
            onChange={(event) => {
              const value = highlightColors.find(
                (value) => value === event.currentTarget.value,
              );
              if (value !== undefined) set({ highlight: value });
            }}
          >
            <option value="" disabled>
              {t.mixed}
            </option>
            {highlightColors.map((value) => (
              <option key={value} value={value}>
                {t[`highlight_${value}`]}
              </option>
            ))}
          </select>
        </label>
        {(["superscript", "subscript"] as const).map((value) => (
          <button
            key={value}
            type="button"
            disabled={disabled}
            aria-pressed={
              character?.vertAlign.kind === "mixed"
                ? "mixed"
                : character?.vertAlign.kind === "value" &&
                  character.vertAlign.value === value
            }
            onClick={() =>
              set({
                vertAlign:
                  character?.vertAlign.kind === "value" &&
                  character.vertAlign.value === value
                    ? "baseline"
                    : value,
              })
            }
          >
            {t[value]}
          </button>
        ))}
      </Group>
      <Group label={t.paragraph}>
        <Command
          label={t.softBreak}
          disabled={disabled}
          action={() => controller.run(() => editor.insertSoftBreak())}
        />
        <Command
          label={t.pageBreak}
          disabled={disabled}
          action={() => controller.run(() => editor.paste(DOCX_PAGE_BREAK))}
        />
        <Command
          label={t.insertTab}
          disabled={disabled}
          action={() => controller.run(() => editor.paste("\t"))}
        />
        {(["left", "center", "right", "both"] as const).map((value) => (
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
                    : value === "right"
                      ? "alignRight"
                      : "alignJustify"
              ]
            }
          </button>
        ))}
        <label>
          <input
            type="checkbox"
            disabled={disabled}
            checked={
              formatting?.paragraph.rtl.kind === "value" &&
              formatting.paragraph.rtl.value
            }
            ref={(node) => {
              if (node)
                node.indeterminate = formatting?.paragraph.rtl.kind === "mixed";
            }}
            onChange={(event) =>
              paragraph({ rtl: event.currentTarget.checked })
            }
          />
          {t.paragraphRtl}
        </label>
        <Command
          label={t.clearParagraph}
          disabled={disabled}
          action={() =>
            paragraph({
              align: null,
              rtl: null,
              before: null,
              after: null,
              left: null,
              right: null,
              first: null,
              line: null,
              tabs: null,
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
  const stylesDisabled = disabled;
  disabled ||= !formatting || !!formatting.reason;
  return (
    <aside className="od-properties" aria-label={t.paragraph}>
      <DocxOverview
        controller={controller}
        state={state}
        editor={editor}
        disabled={stylesDisabled}
      />
      <DocxPage
        controller={controller}
        state={state}
        editor={editor}
        disabled={stylesDisabled}
      />
      <h2>{t.paragraph}</h2>
      <DocxPictures
        key={editor.getSnapshot().documentId}
        controller={controller}
        state={state}
        editor={editor}
        disabled={stylesDisabled}
      />
      <DocxTables
        controller={controller}
        state={state}
        editor={editor}
        disabled={disabled}
      />
      <p>{formatting?.reason}</p>
      <LineSpacing
        controller={controller}
        state={state}
        editor={editor}
        disabled={disabled}
      />
      <DocxTabs
        controller={controller}
        state={state}
        editor={editor}
        disabled={disabled}
      />
      <DocxDefaultTab
        controller={controller}
        state={state}
        editor={editor}
        disabled={stylesDisabled}
      />
      <DocxLists
        controller={controller}
        state={state}
        editor={editor}
        disabled={stylesDisabled}
      />
      <DocxStyles
        kind="paragraph"
        controller={controller}
        state={state}
        editor={editor}
        disabled={stylesDisabled}
      />
      <DocxStyles
        kind="character"
        controller={controller}
        state={state}
        editor={editor}
        disabled={stylesDisabled}
      />
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
      <DocxSearch
        controller={controller}
        state={state}
        editor={editor}
        disabled={
          !!state.document?.busy ||
          !!state.document?.composition ||
          !!state.document?.paused ||
          state.loading
        }
      />
    </aside>
  );
}

function LineSpacing({ controller, state, editor, disabled }: Props) {
  const t = messages(state.locale),
    line = editor.getSnapshot().data.formatting?.paragraph.line;
  const current = line?.kind === "value" ? line.value : undefined;
  const [rule, setRule] = useState<"auto" | "exact" | "atLeast">(
    current?.rule ?? "auto",
  );
  useEffect(() => {
    setRule(current?.rule ?? "auto");
  }, [current?.rule]);
  const value: FormatValue<number> | undefined =
    line?.kind === "value"
      ? {
          kind: "value",
          value: line.value.value / (line.value.rule === "auto" ? 240 : 20),
        }
      : line;
  return (
    <fieldset disabled={disabled}>
      <legend>{t.lineSpacing}</legend>
      <label>
        {t.lineRule}
        <select
          aria-label={t.lineRule}
          value={rule}
          onChange={(event) => {
            const value = event.currentTarget.value;
            if (value === "auto" || value === "exact" || value === "atLeast")
              setRule(value);
          }}
        >
          <option value="auto">{t.lineAuto}</option>
          <option value="exact">{t.lineExact}</option>
          <option value="atLeast">{t.lineAtLeast}</option>
        </select>
      </label>
      {line?.kind === "mixed" && <p>{t.mixed}</p>}
      <NumericFormat
        label={rule === "auto" ? t.lineMultiple : t.linePoints}
        value={value}
        min={rule === "auto" ? 0.5 : 0.05}
        max={rule === "auto" ? 10 : 1584}
        step={rule === "auto" ? 0.1 : 0.05}
        apply={t.apply}
        mixed={t.mixed}
        disabled={disabled}
        onApply={(amount) =>
          controller.run(() =>
            editor.setParagraphFormat({
              line: {
                rule,
                value: Math.round(amount * (rule === "auto" ? 240 : 20)),
              },
            }),
          )
        }
      />
    </fieldset>
  );
}
