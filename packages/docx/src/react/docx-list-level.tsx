import { useState } from "react";
import type { DocumentEditor } from "../web/editor.js";
import {
  listFormats,
  highlightColors,
  type DocxListLevel,
  type DocxListLevelUpdate,
} from "../web/foundation.js";
import type { EditorController, UiSnapshot } from "./context.js";
import { messages } from "@open-document/ui/messages";
import { StyleChoice, StyleInput } from "./docx-style-fields.js";

type MarkerFormat = NonNullable<DocxListLevelUpdate["character"]>;

export function DocxListLevelEdit({
  controller,
  state,
  editor,
  id,
  level,
  availableLevels,
  stale,
  refresh,
}: {
  controller: EditorController;
  state: UiSnapshot;
  editor: DocumentEditor;
  id: number;
  level: DocxListLevel;
  availableLevels: readonly number[];
  stale: boolean;
  refresh: () => Promise<void>;
}) {
  const t = messages(state.locale);
  const label = t.listDefinition;
  const [definition, setDefinition] = useState(level);
  const [start, setStart] = useState(String(level.start));
  const [character, setCharacter] = useState<MarkerFormat>({});
  const [numbers, setNumbers] = useState({ size: "", left: "", first: "" });
  const [color, setColor] = useState("");
  const changeCharacter = <K extends keyof MarkerFormat>(
    key: K,
    value: MarkerFormat[K],
  ) => {
    const next = { ...character };
    if (value === undefined) delete next[key];
    else next[key] = value;
    setCharacter(next);
  };
  const booleans = [
    [true, t.styleOn],
    [false, t.styleOff],
  ] as const;
  const families = Object.keys(controller.options.resources.profile).filter(
    (key) => !key.includes("|"),
  );
  const forbidden = Array.from({ length: 9 }, (_, index) => index)
    .filter((index) => index > level.level || !availableLevels.includes(index))
    .map((index) => index + 1)
    .join("");
  return (
    <form
      onSubmit={(event) => {
        event.preventDefault();
        const marker = { ...character };
        if (numbers.size !== "")
          marker.size =
            numbers.size === "inherit" ? null : Number(numbers.size);
        if (color !== "") marker.color = color === "inherit" ? null : color;
        const update: DocxListLevelUpdate = {
          format: definition.format,
          pattern: definition.pattern,
          start: Number(start),
          restart: definition.restart,
          align: definition.align,
          suffix: definition.suffix,
          character: marker,
        };
        for (const key of ["left", "first"] as const)
          if (numbers[key] !== "")
            update[key] =
              numbers[key] === "inherit" ? null : Number(numbers[key]);
        controller.run(async () => {
          await editor.updateListLevel(id, level.level, update);
          await refresh();
        });
      }}
    >
      {stale && <p role="status">{t.listReload}</p>}
      <fieldset disabled={stale}>
        <legend>{label}</legend>
        <p>{t.listDefinitionScope}</p>
        <label>
          {t.listFormat}
          <select
            aria-label={`${label}: ${t.listFormat}`}
            value={definition.format}
            onChange={(event) => {
              const format = listFormats.find(
                (format) => format === event.currentTarget.value,
              );
              if (format) setDefinition({ ...definition, format });
            }}
          >
            {listFormats.map((format) => (
              <option key={format} value={format}>
                {t[`listFormat_${format}`]}
              </option>
            ))}
          </select>
        </label>
        <label>
          {t.listPattern}
          <input
            aria-label={t.listPattern}
            required
            maxLength={256}
            pattern={forbidden ? `(?!.*%[${forbidden}]).*` : undefined}
            title={t.listPatternHint}
            value={definition.pattern}
            onChange={(event) =>
              setDefinition({
                ...definition,
                pattern: event.currentTarget.value,
              })
            }
          />
        </label>
        <label>
          {t.listDefinitionStart}
          <input
            aria-label={t.listDefinitionStart}
            type="number"
            required
            min={0}
            max={2147483646}
            step={1}
            value={start}
            onChange={(event) => setStart(event.currentTarget.value)}
          />
        </label>
        <label>
          {t.listRestartRule}
          <select
            aria-label={t.listRestartRule}
            value={
              definition.restart === null ? "" : String(definition.restart)
            }
            onChange={(event) =>
              setDefinition({
                ...definition,
                restart:
                  event.currentTarget.value === ""
                    ? null
                    : Number(event.currentTarget.value),
              })
            }
          >
            <option value="">{t.listRestartDefault}</option>
            <option value="0">{t.listRestartNever}</option>
            {Array.from({ length: level.level }, (_, i) => (
              <option key={i} value={i + 1}>
                {t.listRestartAfterLevel} {i + 1}
              </option>
            ))}
          </select>
        </label>
        <label>
          {t.styleAlignment}
          <select
            aria-label={`${label}: ${t.styleAlignment}`}
            value={definition.align}
            onChange={(event) => {
              const align = (["left", "center", "right"] as const).find(
                (value) => value === event.currentTarget.value,
              );
              if (align) setDefinition({ ...definition, align });
            }}
          >
            {(["left", "center", "right"] as const).map((align) => (
              <option key={align} value={align}>
                {
                  t[
                    align === "left"
                      ? "alignLeft"
                      : align === "center"
                        ? "alignCenter"
                        : "alignRight"
                  ]
                }
              </option>
            ))}
          </select>
        </label>
        <label>
          {t.listSuffix}
          <select
            aria-label={t.listSuffix}
            value={definition.suffix}
            onChange={(event) => {
              const suffix = (["tab", "space", "nothing"] as const).find(
                (value) => value === event.currentTarget.value,
              );
              if (suffix) setDefinition({ ...definition, suffix });
            }}
          >
            {(["tab", "space", "nothing"] as const).map((suffix) => (
              <option key={suffix} value={suffix}>
                {t[`listSuffix_${suffix}`]}
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
        {(["size", "left", "first"] as const).map((key) => (
          <StyleInput
            key={key}
            label={`${label}: ${t[key === "size" ? "fontSize" : key === "left" ? "indentLeft" : "firstIndent"]}`}
            locale={state.locale}
            min={key === "size" ? 0.5 : key === "first" ? -1584 : 0}
            max={key === "size" ? 1024 : 1584}
            step={key === "size" ? 0.5 : 0.05}
            value={numbers[key]}
            onChange={(value) => setNumbers({ ...numbers, [key]: value })}
          />
        ))}
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
        <button type="submit">{t.updateListLevel}</button>
      </fieldset>
    </form>
  );
}
