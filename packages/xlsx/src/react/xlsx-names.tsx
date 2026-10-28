import { useState } from "react";
import type { SpreadsheetEditor } from "../web/spreadsheet-editor.js";
import type { EditorController, UiSnapshot } from "./context.js";
import { messages } from "@open-document/ui/messages";

interface NameProps {
  controller: EditorController;
  state: UiSnapshot;
  editor: SpreadsheetEditor;
  disabled: boolean;
}

export function XlsxNames({ controller, state, editor, disabled }: NameProps) {
  const t = messages(state.locale),
    query = editor.currentState;
  const reference = () => {
    const current = editor.currentState;
    const sheet = current.sheets.find((sheet) => sheet.id === current.sheet)!;
    const [first, last = first] = current.selection.address.split(":");
    const fixed = (address: string) =>
      address.replace(/^([A-Z]+)([0-9]+)$/, "$$$1$$$2");
    return `'${sheet.name.replaceAll("'", "''")}'!${fixed(first!)}:${fixed(last!)}`;
  };
  const [chosen, setChosen] = useState("");
  const [name, setName] = useState("");
  const [scope, setScope] = useState<string | null>(null);
  const [formula, setFormula] = useState(reference);
  const identity = (item: { name: string; scope: string | null }) =>
    JSON.stringify([item.scope, item.name]);
  const selected = query.names.entries.find(
    (item) => identity(item) === chosen,
  );
  const reason = query.names.readOnlyReason || selected?.readOnlyReason || "";
  return (
    <section aria-label={t.definedNames}>
      <h3>{t.definedNames}</h3>
      <label>
        {t.definedNameChoice}
        <select
          aria-label={t.definedNameChoice}
          disabled={disabled}
          value={selected ? chosen : ""}
          onChange={(event) => {
            const value = event.currentTarget.value;
            setChosen(value);
            const item = query.names.entries.find(
              (item) => identity(item) === value,
            );
            setName(item?.name ?? "");
            setScope(item?.scope ?? null);
            setFormula(item?.formula ?? reference());
          }}
        >
          <option value="">{t.newDefinedName}</option>
          {query.names.entries.map((item) => (
            <option key={identity(item)} value={identity(item)}>
              {item.name} —{" "}
              {query.sheets.find((sheet) => sheet.id === item.scope)?.name ??
                t.nameWorkbook}
              {item.hidden ? ` (${t.nameHidden})` : ""}
            </option>
          ))}
        </select>
      </label>
      <button
        type="button"
        disabled={disabled || !selected}
        onClick={() => {
          if (selected)
            controller.run(() =>
              editor.editSheet({
                action: "nameSelect",
                name: selected.name,
                scope: selected.scope,
              }),
            );
        }}
      >
        {t.goToDefinedName}
      </button>
      <form
        onSubmit={(event) => {
          event.preventDefault();
          controller.run(() =>
            editor.editSheet({
              action: "name",
              original: selected?.name ?? null,
              name,
              scope,
              formula,
            }),
          );
        }}
      >
        <fieldset disabled={disabled || !!reason}>
          <legend>{selected ? t.editDefinedName : t.newDefinedName}</legend>
          <label>
            {t.definedNameText}
            <input
              required
              maxLength={255}
              value={name}
              onChange={(event) => setName(event.currentTarget.value)}
            />
          </label>
          <label>
            {t.definedNameScope}
            <select
              aria-label={t.definedNameScope}
              disabled={!!selected}
              value={scope ?? ""}
              onChange={(event) => setScope(event.currentTarget.value || null)}
            >
              <option value="">{t.nameWorkbook}</option>
              {query.sheets.map((sheet) => (
                <option key={sheet.id} value={sheet.id}>
                  {sheet.name}
                </option>
              ))}
            </select>
          </label>
          <label>
            {t.definedNameFormula}
            <input
              required
              maxLength={8192}
              value={formula}
              onChange={(event) => setFormula(event.currentTarget.value)}
            />
          </label>
          <button type="button" onClick={() => setFormula(reference())}>
            {t.nameFromSelection}
          </button>
          <button type="submit" disabled={!name || !formula}>
            {selected ? t.applyDefinedName : t.createDefinedName}
          </button>
          <button
            type="button"
            disabled={!selected}
            onClick={() => {
              if (selected)
                controller.run(() =>
                  editor.editSheet({
                    action: "nameDelete",
                    name: selected.name,
                    scope: selected.scope,
                  }),
                );
            }}
          >
            {t.deleteDefinedName}
          </button>
        </fieldset>
      </form>
      {reason && <p>{reason}</p>}
    </section>
  );
}
