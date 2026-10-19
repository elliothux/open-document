import type {
  PptxMasterParagraphFormat,
  PptxMasterParagraphStyle,
} from "@open-document/web/pptx";
import type { UiSnapshot } from "./controller.js";
import { messages } from "./messages.js";
import {
  ParagraphField,
  PptxTabs,
  PptxListFields,
  TextField,
} from "./pptx-format.js";

export function PptxMasterParagraph({
  state,
  paragraph,
  disabled,
  apply,
}: {
  state: UiSnapshot;
  paragraph: PptxMasterParagraphStyle;
  disabled: boolean;
  apply: (format: PptxMasterParagraphFormat | null) => void;
}) {
  const t = messages(state.locale),
    blocked = disabled || !!paragraph.reason;
  return (
    <fieldset disabled={blocked}>
      <legend>{t.pptxMasterParagraph}</legend>
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
          aria-pressed={paragraph.alignment === alignment}
          onClick={() => apply({ alignment })}
        >
          {label}
        </button>
      ))}
      <label>
        <input
          type="checkbox"
          checked={paragraph.rtl === true}
          onChange={(event) => apply({ rtl: event.currentTarget.checked })}
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
      ).map(([property, label]) => (
        <ParagraphField
          key={`${property}:${JSON.stringify(paragraph[property])}`}
          property={property}
          label={label}
          value={paragraph[property]}
          state={state}
          disabled={blocked}
          onApply={apply}
        />
      ))}
      <PptxTabs
        key={`tabs:${JSON.stringify(paragraph.tabs)}:${paragraph.defaultTab}`}
        state={state}
        tabs={paragraph.tabs}
        defaultTab={paragraph.defaultTab}
        disabled={blocked}
        apply={apply}
      />
      <PptxListFields
        key={JSON.stringify(paragraph.list)}
        state={state}
        disabled={blocked}
        list={paragraph.list}
        onApply={apply}
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
          disabled={blocked}
          onApply={(format) => {
            const value = format[property];
            if (typeof value === "string") apply({ [field]: value });
          }}
        />
      ))}
      <ParagraphField
        key={JSON.stringify(paragraph.listSize)}
        property="listSize"
        label={t.listSize}
        value={paragraph.listSize}
        state={state}
        disabled={blocked}
        onApply={apply}
      />
      <button
        type="button"
        onClick={() =>
          apply({ listFont: null, listColor: null, listSize: null })
        }
      >
        {t.listTextStyle}
      </button>
      <button type="button" onClick={() => apply(null)}>
        {t.pptxResetMasterParagraph}
      </button>
      {paragraph.reason && <p>{paragraph.reason}</p>}
    </fieldset>
  );
}
