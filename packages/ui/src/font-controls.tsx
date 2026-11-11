import { Fragment, useEffect, useRef, useState } from "react";
import type { CommandTarget, EditorCommandApi } from "./commands.js";
import { Icon } from "./icons.js";
import { messages } from "./messages.js";
import type { Locale } from "./types.js";

export type EditorFontChange = { family: string } | { size: number };

export interface EditorFontControlsProps {
  readonly commands: Pick<EditorCommandApi, "captureTarget">;
  readonly locale: Locale;
  readonly profile: Readonly<Record<string, string>>;
  readonly family: string | null;
  readonly size: number | null | undefined;
  readonly minSize: number;
  readonly maxSize: number;
  readonly sizeStep: number | "any";
  readonly disabled: boolean;
  apply(change: EditorFontChange, target: CommandTarget): void;
}

/** Native font controls. The host applies the change through its format transaction. */
export function EditorFontControls(props: EditorFontControlsProps) {
  const { commands, locale, family, profile, disabled, apply } = props;
  const t = messages(locale);
  const families = new Set(
    Object.keys(profile).filter(
      (key) => key && key !== "*" && !key.includes("|"),
    ),
  );
  if (family) families.add(family);
  const target = commands.captureTarget();
  const scope = JSON.stringify([target?.documentId, target?.selection]);
  return (
    <Fragment key={scope}>
      <select
        className="od-font-family"
        aria-label={t.fontFamily}
        title={family ?? t.mixed}
        value={family ?? ""}
        disabled={disabled || !target || !families.size}
        onChange={(event) => {
          if (target) apply({ family: event.currentTarget.value }, target);
        }}
      >
        <option value="" disabled>
          {t.mixed}
        </option>
        {[...families].map((name) => (
          <option key={name}>{name}</option>
        ))}
      </select>
      <FontSizeField {...props} disabled={disabled || !target} />
    </Fragment>
  );
}

function FontSizeField({
  commands,
  locale,
  size,
  minSize,
  maxSize,
  sizeStep,
  disabled,
  apply,
}: EditorFontControlsProps) {
  const t = messages(locale);
  const submitLabel = `${t.apply} ${t.fontSize}`;
  const current = size == null ? "" : String(size);
  const [draft, setDraft] = useState(current);
  const target = useRef<CommandTarget | undefined>(undefined);
  useEffect(() => {
    target.current = undefined;
    setDraft(current);
  }, [current]);

  return (
    <form
      className="od-font-size"
      onSubmit={(event) => {
        event.preventDefault();
        const pending = target.current ?? commands.captureTarget();
        if (pending && !disabled && draft !== "")
          apply({ size: Number(draft) }, pending);
      }}
    >
      <input
        aria-label={t.fontSize}
        title={t.fontSize}
        type="number"
        required
        min={minSize}
        max={maxSize}
        step={sizeStep}
        disabled={disabled}
        value={draft}
        placeholder={size === null ? t.mixed : ""}
        onChange={(event) => {
          target.current ??= commands.captureTarget();
          setDraft(event.currentTarget.value);
        }}
        onKeyDown={(event) => {
          if (event.key !== "Escape") return;
          target.current = undefined;
          setDraft(current);
        }}
      />
      <button
        type="submit"
        className="od-icon-command"
        aria-label={submitLabel}
        title={submitLabel}
        disabled={disabled || draft === ""}
      >
        <Icon name="check" />
      </button>
    </form>
  );
}
