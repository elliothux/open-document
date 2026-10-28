import type { Locale } from "@open-document/ui/types";
import { messages } from "@open-document/ui/messages";

export function StyleChoice<T extends string | boolean>({
  label,
  locale,
  value,
  options,
  onChange,
}: {
  label: string;
  locale: Locale;
  value: T | null | undefined;
  options: ReadonlyArray<readonly [T, string]>;
  onChange: (value: T | null | undefined) => void;
}) {
  const t = messages(locale);
  const index = options.findIndex(([item]) => item === value);
  return (
    <label>
      {label}
      <select
        aria-label={label}
        value={value === null ? "inherit" : index < 0 ? "" : `v${index}`}
        onChange={(event) => {
          const next = event.currentTarget.value;
          if (next === "") onChange(undefined);
          else if (next === "inherit") onChange(null);
          else {
            const option = options.find((_, index) => next === `v${index}`);
            if (option) onChange(option[0]);
          }
        }}
      >
        <option value="">{t.keepStyleProperty}</option>
        <option value="inherit">{t.inheritStyleProperty}</option>
        {options.map(([item, text], index) => (
          <option key={String(item)} value={`v${index}`}>
            {text}
          </option>
        ))}
      </select>
    </label>
  );
}

/** Empty retains the definition; inherit clears it; other strings are drafts. */
export function StyleInput({
  label,
  locale,
  value,
  onChange,
  type = "number",
  min,
  max,
  step,
}: {
  label: string;
  locale: Locale;
  value: string;
  onChange: (value: string) => void;
  type?: "number" | "color";
  min?: number;
  max?: number;
  step?: number;
}) {
  const t = messages(locale);
  return (
    <div>
      <label>
        {label}
        <input
          aria-label={label}
          type={type === "color" ? "text" : "number"}
          pattern={type === "color" ? "([a-fA-F0-9]{6}|auto)" : undefined}
          min={min}
          max={max}
          step={step}
          placeholder={t.keepStyleProperty}
          disabled={value === "inherit"}
          value={value === "inherit" ? "" : value}
          onChange={(event) => onChange(event.currentTarget.value)}
        />
      </label>
      <label>
        {t.styleValueMode}
        <select
          aria-label={`${label}: ${t.styleValueMode}`}
          value={value === "inherit" ? "inherit" : value === "" ? "" : "set"}
          onChange={(event) => {
            const mode = event.currentTarget.value;
            onChange(
              mode === "inherit"
                ? "inherit"
                : mode === "set"
                  ? type === "color"
                    ? "auto"
                    : String(Math.max(0, min ?? 0))
                  : "",
            );
          }}
        >
          <option value="">{t.keepStyleProperty}</option>
          <option value="set">{t.setStyleProperty}</option>
          <option value="inherit">{t.inheritStyleProperty}</option>
        </select>
      </label>
    </div>
  );
}
