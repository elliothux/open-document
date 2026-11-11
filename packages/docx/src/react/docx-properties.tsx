import type { FormatValue } from "../web/foundation.js";
import { DocxProtection } from "./docx-protection.js";
import { useEffect, useRef, useState } from "react";
import { docxHyperlinkTargetUnits } from "@open-document/wasm/engine-source";
import { EditorPanel } from "@open-document/ui";
import { messages } from "@open-document/ui/messages";
import { DocxSearch } from "./docx-search.js";
import { DocxOverview } from "./docx-overview.js";
import { DocxComments } from "./docx-comments.js";
import { DocxRevisions } from "./docx-revisions.js";
import { DocxTabs, DocxDefaultTab } from "./docx-tabs.js";
import { DocxStyles } from "./docx-styles.js";
import { DocxLists } from "./docx-lists.js";
import { DocxPage } from "./docx-page.js";
import { DocxTheme, DocxThemeFontsPanel } from "./docx-theme.js";
import { DocxPictures } from "./docx-pictures.js";
import { DocxShapes } from "./docx-shapes.js";
import { DocxCharts } from "./docx-charts.js";
import { DocxMath } from "./docx-math.js";
import { DocxTables } from "./docx-tables.js";
import { checkDocxHyperlink } from "../web/foundation.js";
import {
  DocxFormatCommands,
  NumericFormat,
  type DocxPanelProps,
} from "./docx-format.js";
import { Icon } from "@open-document/ui/icons";
import type { IconName } from "@open-document/ui/icons";

const taskIcons: Partial<Record<string, IconName>> = {
  find: "search",
  font: "font-size",
  paragraph: "paragraph-spacing",
  styles: "format-painter",
  table: "table-cells",
  "insert-picture": "image",
  illustrations: "shapes",
  link: "link-plus",
  math: "function-fx",
  layout: "page-margins",
  running: "layout-header",
  design: "palette",
  references: "table-of-contents",
  notes: "list-ordered",
  review: "comment-count",
};

export function DocxProperties({
  controller,
  state,
  editor,
  disabled,
  task,
  close,
}: DocxPanelProps & { task: string; close(): void }) {
  const t = messages(state.locale),
    formatting = editor.getSnapshot().data.formatting;
  const stylesDisabled = disabled;
  const inputDisabled = disabled || !formatting || !!formatting.inputReason;
  const paragraphDisabled =
    disabled || !formatting || !!formatting.paragraphReason;
  disabled ||= !formatting || !!formatting.reason;
  let content;
  let label: string;
  switch (task) {
    case "font":
      label = t.fontOptions;
      content = (
        <>
          <DocxFormatCommands
            controller={controller}
            state={state}
            editor={editor}
            disabled={stylesDisabled}
            section="advanced"
          />
        </>
      );
      break;
    case "paragraph":
      label = t.paragraphOptions;
      content = (
        <>
          <LineSpacing
            controller={controller}
            state={state}
            editor={editor}
            disabled={paragraphDisabled}
          />
          <DocxTabs
            controller={controller}
            state={state}
            editor={editor}
            disabled={paragraphDisabled}
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
          {(["before", "after", "left", "right", "first"] as const).map(
            (key) => (
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
                disabled={paragraphDisabled}
                apply={t.apply}
                mixed={t.mixed}
                onApply={(value) =>
                  controller.run(() =>
                    editor.formatting.setParagraphFormat({ [key]: value }),
                  )
                }
              />
            ),
          )}
          {(
            [
              "pageBreakBefore",
              "keepLines",
              "keepNext",
              "widowControl",
            ] as const
          ).map((key) => (
            <label key={key}>
              <input
                type="checkbox"
                ref={(node) => {
                  if (node)
                    node.indeterminate =
                      formatting?.paragraph[key].kind === "mixed";
                }}
                disabled={paragraphDisabled}
                checked={
                  formatting?.paragraph[key].kind === "value" &&
                  formatting.paragraph[key].value
                }
                onChange={(event) =>
                  controller.run(() =>
                    editor.formatting.setParagraphFormat({
                      [key]: event.currentTarget.checked,
                    }),
                  )
                }
              />
              {t[key]}
            </label>
          ))}
        </>
      );
      break;
    case "styles":
      label = t.stylesPanel;
      content = (
        <>
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
        </>
      );
      break;
    case "design":
      label = t.theme;
      content = (
        <>
          <DocxTheme
            key={`theme:${editor.getSnapshot().documentId}`}
            controller={controller}
            state={state}
            editor={editor}
            disabled={stylesDisabled}
          />
          <DocxThemeFontsPanel
            key={editor.getSnapshot().documentId + "-fonts"}
            controller={controller}
            state={state}
            editor={editor}
            disabled={stylesDisabled}
          />
        </>
      );
      break;
    case "references":
      label = t.referencesTab;
      content = (
        <>
          <DocxOverview
            controller={controller}
            state={state}
            editor={editor}
            disabled={stylesDisabled}
          />
        </>
      );
      break;
    case "review":
      label = t.reviewTab;
      content = (
        <>
          <DocxRevisions
            controller={controller}
            state={state}
            editor={editor}
            disabled={stylesDisabled}
          />
          <DocxComments
            key={`comments:${state.document?.documentId}`}
            controller={controller}
            state={state}
            editor={editor}
            disabled={stylesDisabled}
          />

          <DocxProtection
            controller={controller}
            state={state}
            editor={editor}
            disabled={stylesDisabled}
          />
        </>
      );
      break;
    case "running":
    case "notes":
      label = task === "running" ? t.headerFooterTab : t.noteNumbering;
      content = (
        <DocxPage
          controller={controller}
          state={state}
          editor={editor}
          disabled={stylesDisabled}
          task={task}
        />
      );
      break;
    case "layout":
      label = t.layoutTab;
      content = (
        <>
          <DocxPage
            key={`page:${editor.getSnapshot().documentId}`}
            controller={controller}
            state={state}
            editor={editor}
            disabled={stylesDisabled}
          />
        </>
      );
      break;
    case "insert-picture":
      label = t.pictureTab;
      content = (
        <>
          <DocxPictures
            key={`pictures:${editor.getSnapshot().documentId}`}
            controller={controller}
            state={state}
            editor={editor}
            disabled={stylesDisabled}
          />
        </>
      );
      break;
    case "illustrations":
      label = t.insertObjects;
      content = (
        <>
          <DocxShapes
            key={`shapes:${editor.getSnapshot().documentId}`}
            controller={controller}
            state={state}
            editor={editor}
            disabled={stylesDisabled}
          />
          <DocxCharts
            key={editor.getSnapshot().documentId + "-charts"}
            controller={controller}
            state={state}
            editor={editor}
            disabled={stylesDisabled}
            insertDisabled={inputDisabled}
          />
        </>
      );
      break;
    case "math":
      label = t.mathExpressions;
      content = (
        <>
          <DocxMath
            key={`math:${editor.getSnapshot().documentId}`}
            kind="expression"
            controller={controller}
            state={state}
            editor={editor}
            disabled={stylesDisabled}
            insertDisabled={inputDisabled}
          />
          <DocxMath
            key={editor.getSnapshot().documentId + "-fractions"}
            kind="fraction"
            controller={controller}
            state={state}
            editor={editor}
            disabled={stylesDisabled}
            insertDisabled={inputDisabled}
          />
          <DocxMath
            key={editor.getSnapshot().documentId + "-scripts"}
            kind="script"
            controller={controller}
            state={state}
            editor={editor}
            disabled={stylesDisabled}
            insertDisabled={inputDisabled}
          />
        </>
      );
      break;
    case "table":
      label = t.tableTab;
      content = (
        <>
          <DocxTables
            controller={controller}
            state={state}
            editor={editor}
            disabled={stylesDisabled}
          />
        </>
      );
      break;
    case "link":
      label = t.textHyperlink;
      content = (
        <>
          <DocxHyperlink
            key={`link:${state.document?.documentId}`}
            controller={controller}
            state={state}
            editor={editor}
            disabled={disabled}
          />
        </>
      );
      break;
    case "find":
      label = t.findReplace;
      content = (
        <>
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
        </>
      );
      break;
    default:
      return null;
  }
  return (
    <EditorPanel
      label={label}
      icon={taskIcons[task]}
      closeLabel={t.closePanel}
      close={close}
    >
      {content}
    </EditorPanel>
  );
}

function DocxHyperlink({
  controller,
  state,
  editor,
  disabled,
}: DocxPanelProps) {
  const t = messages(state.locale),
    current = editor.getSnapshot().data,
    link = current.formatting?.hyperlink,
    selection = current.selection;
  const [address, setAddress] = useState(link?.target ?? ""),
    [text, setText] = useState("");
  const source = useRef(link);
  useEffect(() => {
    if (
      !link ||
      (link.target === source.current?.target &&
        link.mixed === source.current?.mixed)
    )
      return;
    source.current = link;
    setAddress(link.target ?? "");
    setText("");
  }, [link]);
  const needsText =
    !link?.target &&
    !link?.mixed &&
    selection?.anchor.paragraph === selection?.focus.paragraph &&
    selection?.anchor.offset === selection?.focus.offset;
  disabled ||= !link || !!link.reason;
  return (
    <section aria-label={t.textHyperlink}>
      <form
        onSubmit={(event) => {
          event.preventDefault();
          controller.run(() => {
            checkDocxHyperlink(address, text || undefined);
            return editor.formatting.setHyperlink(address, text || undefined);
          });
        }}
      >
        <fieldset disabled={disabled}>
          <legend>
            <Icon name="link" />
            {t.textHyperlink}
          </legend>
          <label>
            {t.hyperlinkAddress}
            <input
              type="text"
              inputMode="url"
              required
              maxLength={docxHyperlinkTargetUnits}
              value={address}
              onChange={(event) => setAddress(event.currentTarget.value)}
            />
          </label>
          <p>{t.hyperlinkBookmark}</p>
          <label>
            {t.hyperlinkText}
            <input
              type="text"
              required={needsText}
              maxLength={65536}
              value={text}
              onChange={(event) => setText(event.currentTarget.value)}
            />
          </label>
          <button type="submit">
            <Icon name="check" />
            {t.hyperlinkApply}
          </button>
          <button
            type="button"
            disabled={!link?.target && !link?.mixed}
            onClick={() =>
              controller.run(() => editor.formatting.setHyperlink(null))
            }
          >
            <Icon name="trash" />
            {t.hyperlinkRemove}
          </button>
        </fieldset>
      </form>
      {link?.reason && <p>{link.reason}</p>}
      {!disabled &&
        link?.target &&
        (link.target.startsWith("#") ? (
          <button
            type="button"
            onClick={() =>
              controller.run(() =>
                editor.review.editBookmark({
                  action: "goTo",
                  name: link.target!.slice(1),
                }),
              )
            }
          >
            <Icon name="arrow-right" />
            {t.hyperlinkOpen}
          </button>
        ) : (
          <a href={link.target} target="_blank" rel="noopener noreferrer">
            {t.hyperlinkOpen}
          </a>
        ))}
    </section>
  );
}

function LineSpacing({ controller, state, editor, disabled }: DocxPanelProps) {
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
      <legend>
        <Icon name="paragraph-spacing" />
        {t.lineSpacing}
      </legend>
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
            editor.formatting.setParagraphFormat({
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
