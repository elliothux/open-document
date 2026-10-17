import { useEffect, useState } from "react";
import type { DocumentEditor } from "@open-document/web/editor";
import type {
  CharacterFormatPatch,
  DocxStyleCatalog,
  ParagraphFormatPatch,
} from "@open-document/web/foundation";
import { highlightColors } from "@open-document/web/foundation";
import type { EditorController, UiSnapshot } from "./controller.js";
import { messages } from "./messages.js";
import { StyleChoice, StyleInput } from "./docx-style-fields.js";
import { DocxTabFields } from "./docx-tab-fields.js";

const emptyNumbers = {
  size: "",
  before: "",
  after: "",
  left: "",
  right: "",
  first: "",
};

export function DocxStyleEdit({
  controller,
  state,
  editor,
  kind,
  choice,
  styles,
  refresh,
}: {
  controller: EditorController;
  state: UiSnapshot;
  editor: DocumentEditor;
  kind: "paragraph" | "character";
  choice: DocxStyleCatalog["styles"][number] | undefined;
  styles: DocxStyleCatalog["styles"];
  refresh: () => Promise<void>;
}) {
  const t = messages(state.locale);
  const label = kind === "paragraph" ? t.paragraphStyle : t.characterStyle;
  const [name, setName] = useState(choice?.name ?? "");
  const [basedOn, setBasedOn] = useState(choice?.basedOn ?? "");
  const [character, setCharacter] = useState<CharacterFormatPatch>({});
  const [paragraph, setParagraph] = useState<ParagraphFormatPatch>({});
  const [numbers, setNumbers] = useState(emptyNumbers);
  const [color, setColor] = useState("");
  const [lineRule, setLineRule] = useState<
    "auto" | "exact" | "atLeast" | null | undefined
  >();
  const [lineAmount, setLineAmount] = useState("1");
  const reset = () => {
    setCharacter({});
    setParagraph({});
    setNumbers(emptyNumbers);
    setColor("");
    setLineRule(undefined);
    setLineAmount("1");
  };
  useEffect(() => {
    setName(choice?.name ?? "");
    setBasedOn(choice?.basedOn ?? "");
    reset();
  }, [choice?.id, choice?.name, choice?.basedOn, editor]);
  const changeCharacter = <K extends keyof CharacterFormatPatch>(
    key: K,
    value: CharacterFormatPatch[K],
  ) => {
    const next = { ...character };
    if (value === undefined) delete next[key];
    else next[key] = value;
    setCharacter(next);
  };
  const changeParagraph = <K extends keyof ParagraphFormatPatch>(
    key: K,
    value: ParagraphFormatPatch[K],
  ) => {
    const next = { ...paragraph };
    if (value === undefined) delete next[key];
    else next[key] = value;
    setParagraph(next);
  };
  const booleans = [
    [true, t.styleOn],
    [false, t.styleOff],
  ] as const;
  const families = Object.keys(controller.options.resources.profile).filter(
    (key) => !key.includes("|"),
  );
  return (
    <form
      onSubmit={(event) => {
        event.preventDefault();
        if (!choice) return;
        const characterPatch = { ...character },
          paragraphPatch = { ...paragraph };
        for (const key of [
          "size",
          "before",
          "after",
          "left",
          "right",
          "first",
        ] as const) {
          const draft = numbers[key];
          if (draft !== "") {
            const value = draft === "inherit" ? null : Number(draft);
            if (key === "size") characterPatch.size = value;
            else paragraphPatch[key] = value;
          }
        }
        if (color !== "")
          characterPatch.color = color === "inherit" ? null : color;
        if (paragraphPatch.tabs)
          paragraphPatch.tabs = [...paragraphPatch.tabs].sort(
            (a, b) => a.position - b.position,
          );
        if (lineRule === null) paragraphPatch.line = null;
        else if (lineRule !== undefined)
          paragraphPatch.line = {
            rule: lineRule,
            value: Math.round(
              Number(lineAmount) * (lineRule === "auto" ? 240 : 20),
            ),
          };
        controller.run(async () => {
          await editor.updateStyle(choice.id, {
            character: characterPatch,
            paragraph: paragraphPatch,
            name,
            basedOn: basedOn || null,
          });
          reset();
          await refresh();
        });
      }}
    >
      <fieldset disabled={!choice || !!choice.reason}>
        <legend>{t.editStyle}</legend>
        <label>
          {t.styleName}
          <input
            aria-label={`${label}: ${t.styleName}`}
            required
            maxLength={200}
            value={name}
            onChange={(event) => setName(event.currentTarget.value)}
          />
        </label>
        <label>
          {t.styleBasedOn}
          <select
            aria-label={`${label}: ${t.styleBasedOn}`}
            value={basedOn}
            onChange={(event) => setBasedOn(event.currentTarget.value)}
          >
            <option value="">{t.noBaseStyle}</option>
            {styles
              .filter((style) => style.id !== choice?.id)
              .map((style) => (
                <option
                  key={style.id}
                  value={style.id}
                  disabled={!!style.reason}
                >
                  {style.name}
                </option>
              ))}
          </select>
        </label>
        <StyleChoice
          label={`${label}: ${t.fontFamily}`}
          locale={state.locale}
          value={character.family}
          options={families.map((family) => [family, family] as const)}
          onChange={(value) => changeCharacter("family", value)}
        />
        <StyleInput
          label={`${label}: ${t.fontSize}`}
          locale={state.locale}
          min={0.5}
          max={1024}
          step={0.5}
          value={numbers.size}
          onChange={(size) => setNumbers({ ...numbers, size })}
        />
        {(["bold", "italic", "underline", "strike"] as const).map((key) => (
          <StyleChoice
            key={key}
            label={`${label}: ${t[key]}`}
            locale={state.locale}
            value={character[key]}
            options={booleans}
            onChange={(value) => changeCharacter(key, value)}
          />
        ))}
        <StyleInput
          label={`${label}: ${t.textColor}`}
          locale={state.locale}
          type="color"
          value={color}
          onChange={setColor}
        />
        <StyleChoice
          label={`${label}: ${t.highlightColor}`}
          locale={state.locale}
          value={character.highlight}
          options={highlightColors.map(
            (value) => [value, t[`highlight_${value}`]] as const,
          )}
          onChange={(value) => changeCharacter("highlight", value)}
        />
        <StyleChoice
          label={`${label}: ${t.scriptPosition}`}
          locale={state.locale}
          value={character.vertAlign}
          options={[
            ["baseline", t.baseline],
            ["superscript", t.superscript],
            ["subscript", t.subscript],
          ]}
          onChange={(value) => changeCharacter("vertAlign", value)}
        />
        {kind === "paragraph" && (
          <>
            <StyleChoice
              label={`${label}: ${t.styleAlignment}`}
              locale={state.locale}
              value={paragraph.align}
              options={[
                ["left", t.alignLeft],
                ["center", t.alignCenter],
                ["right", t.alignRight],
                ["both", t.alignJustify],
              ]}
              onChange={(value) => changeParagraph("align", value)}
            />
            {(["rtl", "pageBreakBefore", "keepLines"] as const).map((key) => (
              <StyleChoice
                key={key}
                label={`${label}: ${key === "rtl" ? t.paragraphRtl : t[key]}`}
                locale={state.locale}
                value={paragraph[key]}
                options={booleans}
                onChange={(value) => changeParagraph(key, value)}
              />
            ))}
            {(["before", "after", "left", "right", "first"] as const).map(
              (key) => (
                <StyleInput
                  key={key}
                  label={`${label}: ${t[key === "before" ? "spaceBefore" : key === "after" ? "spaceAfter" : key === "left" ? "indentLeft" : key === "right" ? "indentRight" : "firstIndent"]}`}
                  locale={state.locale}
                  min={key === "first" ? -1584 : 0}
                  max={1584}
                  step={0.05}
                  value={numbers[key]}
                  onChange={(value) => setNumbers({ ...numbers, [key]: value })}
                />
              ),
            )}
            <StyleChoice
              label={`${label}: ${t.lineRule}`}
              locale={state.locale}
              value={lineRule}
              options={[
                ["auto", t.lineAuto],
                ["exact", t.lineExact],
                ["atLeast", t.lineAtLeast],
              ]}
              onChange={setLineRule}
            />
            <label>
              {lineRule === "auto" ? t.lineMultiple : t.linePoints}
              <input
                aria-label={`${label}: ${lineRule === "auto" ? t.lineMultiple : t.linePoints}`}
                type="number"
                disabled={!lineRule}
                required={!!lineRule}
                min={lineRule === "auto" ? 0.5 : 0.05}
                max={lineRule === "auto" ? 10 : 1584}
                step={0.05}
                value={lineAmount}
                onChange={(event) => setLineAmount(event.currentTarget.value)}
              />
            </label>
            <label>
              {t.tabStops}
              <select
                aria-label={`${label}: ${t.tabStops}`}
                value={
                  paragraph.tabs === null
                    ? "inherit"
                    : paragraph.tabs === undefined
                      ? ""
                      : "set"
                }
                onChange={(event) => {
                  const mode = event.currentTarget.value;
                  changeParagraph(
                    "tabs",
                    mode === "inherit" ? null : mode === "set" ? [] : undefined,
                  );
                }}
              >
                <option value="">{t.keepStyleProperty}</option>
                <option value="inherit">{t.inheritStyleProperty}</option>
                <option value="set">{t.setStyleProperty}</option>
              </select>
            </label>
            {paragraph.tabs && (
              <DocxTabFields
                prefix={`${label}: `}
                locale={state.locale}
                draft={paragraph.tabs}
                setDraft={(tabs) => changeParagraph("tabs", tabs)}
              />
            )}
          </>
        )}
        <button type="submit">
          {kind === "paragraph"
            ? t.updateParagraphStyle
            : t.updateCharacterStyle}
        </button>
      </fieldset>
    </form>
  );
}
