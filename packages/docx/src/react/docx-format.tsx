import {
  EditorColorPalette,
  EditorCommandButton,
  EditorFontControls,
} from "@open-document/ui";
import { useEffect, useState } from "react";
import type { DocumentEditor } from "../web/editor.js";
import type {
  FormatValue,
  CharacterFormatPatch,
  ParagraphFormatPatch,
  CopiedFormat,
} from "../web/foundation.js";
import {
  highlightColors,
  DOCX_PAGE_BREAK,
  DOCX_COLUMN_BREAK,
} from "../web/foundation.js";
import type { EditorController, UiSnapshot } from "./context.js";
import { Icon } from "@open-document/ui/icons";
import { Command, Group } from "@open-document/ui/controls";
import { messages } from "@open-document/ui/messages";
import { DocxSymbols } from "./docx-symbols.js";
import { RibbonMenu } from "@open-document/ui/ribbon";

export interface DocxPanelProps {
  controller: EditorController;
  state: UiSnapshot;
  editor: DocumentEditor;
  disabled: boolean;
}

export function NumericFormat({
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
        <span className="od-field-caption">{label}</span>
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
  section = "home",
  portal,
}: DocxPanelProps & {
  section?: "home" | "advanced" | "insert";
  portal?: HTMLElement;
}) {
  const t = messages(state.locale),
    formatting = editor.getSnapshot().data.formatting;
  const character = formatting?.character;
  const fontDisabled = disabled || !formatting || !!formatting.fontReason;
  const paragraphDisabled =
    disabled || !formatting || !!formatting.paragraphReason;
  disabled ||= !formatting || !!formatting.reason;
  const set = (format: CharacterFormatPatch) =>
    controller.run(() => editor.formatting.setCharacterFormat(format));
  const paragraph = (format: ParagraphFormatPatch) =>
    controller.run(() => editor.formatting.setParagraphFormat(format));
  const currentColor =
    character?.color.kind === "value" && character.color.value !== "auto"
      ? character.color.value
      : "000000";
  const [color, setColor] = useState(currentColor);
  const [copied, setCopied] = useState<CopiedFormat>();
  useEffect(() => setCopied(undefined), [editor]);
  useEffect(() => setColor(currentColor), [currentColor]);
  const align = formatting?.paragraph.align;
  if (section === "insert")
    return !portal ? null : (
      <>
        <RibbonMenu
          label={t.breaks}
          portal={portal}
          className="od-command"
          disabled={disabled}
          actions={[
            {
              label: t.pageBreak,
              icon: "page-break",
              run: () => controller.run(() => editor.paste(DOCX_PAGE_BREAK)),
            },
            {
              label: t.columnBreak,
              icon: "columns-2",
              run: () => controller.run(() => editor.paste(DOCX_COLUMN_BREAK)),
            },
            {
              label: t.softBreak,
              icon: "wrap-text",
              run: () =>
                controller.run(() => editor.clipboard.insertSoftBreak()),
            },
            {
              label: t.insertTab,
              icon: "key-tab",
              run: () => controller.run(() => editor.paste("\t")),
            },
          ]}
        >
          <Icon name="page-break" />
          <span>{t.breaks}</span>
          <Icon name="chevron-down" />
        </RibbonMenu>
        <DocxSymbols
          controller={controller}
          state={state}
          editor={editor}
          disabled={disabled}
          portal={portal}
        />
      </>
    );
  if (section === "advanced")
    return (
      <div className="od-format-options">
        <Group label={t.font}>
          <Command
            label={t.copyFormat}
            icon="copy"
            disabled={disabled}
            action={() =>
              controller.run(async () =>
                setCopied(await editor.formatting.captureFormat()),
              )
            }
          />
          <Command
            label={t.applyFormat}
            icon="check"
            disabled={disabled || !copied}
            action={() =>
              controller.run(() =>
                copied
                  ? editor.formatting.applyFormat(copied)
                  : Promise.resolve(),
              )
            }
          />
          <NumericFormat
            label={t.characterSpacing}
            value={character?.spacing}
            min={-1584}
            max={1584}
            step={0.05}
            disabled={disabled}
            apply={t.apply}
            mixed={t.mixed}
            onApply={(spacing) => set({ spacing })}
          />
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
              disabled={fontDisabled}
              onChange={(event) => setColor(event.currentTarget.value.slice(1))}
            />
          </label>
          <Command
            label={t.applyColor}
            icon="check"
            disabled={fontDisabled}
            action={() => set({ color })}
          />
          <Command
            label={t.clearFont}
            icon="eraser"
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
                spacing: null,
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
          <label>
            <input
              type="checkbox"
              disabled={paragraphDisabled}
              checked={
                formatting?.paragraph.rtl.kind === "value" &&
                formatting.paragraph.rtl.value
              }
              ref={(node) => {
                if (node)
                  node.indeterminate =
                    formatting?.paragraph.rtl.kind === "mixed";
              }}
              onChange={(event) =>
                paragraph({ rtl: event.currentTarget.checked })
              }
            />
            {t.paragraphRtl}
          </label>
          <Command
            label={t.clearParagraph}
            icon="eraser"
            disabled={paragraphDisabled}
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
                keepLines: null,
                keepNext: null,
                widowControl: null,
              })
            }
          />
        </Group>
      </div>
    );
  return (
    <>
      <Group label={t.font}>
        <EditorFontControls
          commands={controller.commands}
          locale={state.locale}
          profile={controller.options.resources.profile}
          family={
            character?.family.kind === "value" ? character.family.value : null
          }
          size={
            character?.size.kind === "value"
              ? character.size.value
              : character?.size.kind === "mixed"
                ? null
                : undefined
          }
          minSize={0.5}
          maxSize={1024}
          sizeStep={0.5}
          disabled={fontDisabled}
          apply={(change, target) =>
            controller.run(() =>
              editor.formatting.setCharacterFormat(change, () =>
                controller.commands.assertTarget(target),
              ),
            )
          }
        />
        {(["bold", "italic", "underline", "strike"] as const).map((id) => (
          <EditorCommandButton key={id} id={id} iconOnly />
        ))}
        {portal && (
          <EditorColorPalette
            commands={controller.commands}
            label={t.textColor}
            custom={t.customColor}
            mixed={t.mixed}
            value={character?.color.kind === "mixed" ? null : currentColor}
            disabled={fontDisabled}
            portal={portal}
            apply={(color, target) =>
              controller.run(() =>
                editor.formatting.setCharacterFormat({ color }, () =>
                  controller.commands.assertTarget(target),
                ),
              )
            }
          />
        )}
      </Group>
      <Group label={t.paragraph}>
        {(["left", "center", "right", "both"] as const).map((value) => (
          <button
            key={value}
            type="button"
            className="od-icon-command"
            disabled={paragraphDisabled}
            aria-pressed={
              align?.kind === "mixed"
                ? "mixed"
                : align?.kind === "value" && align.value === value
            }
            aria-label={
              t[
                value === "both"
                  ? "alignJustify"
                  : value === "left"
                    ? "alignLeft"
                    : value === "center"
                      ? "alignCenter"
                      : "alignRight"
              ]
            }
            title={
              t[
                value === "both"
                  ? "alignJustify"
                  : value === "left"
                    ? "alignLeft"
                    : value === "center"
                      ? "alignCenter"
                      : "alignRight"
              ]
            }
            onClick={() => paragraph({ align: value })}
          >
            <Icon
              name={
                value === "both"
                  ? "align-justify"
                  : value === "left"
                    ? "align-left"
                    : value === "center"
                      ? "align-center"
                      : "align-right"
              }
            />
          </button>
        ))}
      </Group>
    </>
  );
}
