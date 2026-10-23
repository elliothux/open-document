import type {
  XlsxPivotBaseItem,
  XlsxPivotPreview,
} from "@open-document/web/xlsx";
import type { UiSnapshot } from "./controller.js";
import { messages } from "./messages.js";

export function PivotBaseItemSelect({
  value,
  items,
  update,
  state,
}: {
  value: XlsxPivotBaseItem | null;
  items: XlsxPivotPreview["baseItems"][number] | undefined;
  update(value: XlsxPivotBaseItem): void;
  state: UiSnapshot;
}) {
  const t = messages(state.locale);
  const at =
    items?.findIndex(
      (item) => JSON.stringify(item.value) === JSON.stringify(value),
    ) ?? -1;
  const selected =
    typeof value === "string" ? value : at < 0 ? "retained" : "member:" + at;
  return (
    <label>
      {t.pivotBaseItem}
      <select
        aria-label={t.pivotBaseItem}
        value={selected}
        onChange={(event) => {
          const selected = event.currentTarget.value;
          if (selected === "previous" || selected === "next") update(selected);
          else {
            const item = items?.[Number(selected.slice(7))];
            if (item) update(item.value);
          }
        }}
      >
        <option value="previous">{t.pivotPrevious}</option>
        <option value="next">{t.pivotNext}</option>
        {typeof value === "object" && value && at < 0 && (
          <option value="retained">
            {String(value.value ?? t.pivotBlank)}
          </option>
        )}
        {items?.map((item, index) => (
          <option key={index} value={"member:" + index}>
            {item.label} ({t[`pivotFilterKind_${item.value.kind}`]})
          </option>
        ))}
      </select>
      {!items?.length && <span>{t.pivotBaseItemLoad}</span>}
    </label>
  );
}
