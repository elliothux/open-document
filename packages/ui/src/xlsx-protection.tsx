import { useState } from "react";
import type { SpreadsheetEditor } from "@open-document/web/spreadsheet-editor";
import type { EditorController, UiSnapshot } from "./controller.js";
import { messages } from "./messages.js";

export function XlsxProtection({
  controller,
  state,
  editor,
  disabled,
  workbook = false,
}: {
  controller: EditorController;
  state: UiSnapshot;
  editor: SpreadsheetEditor;
  disabled: boolean;
  workbook?: boolean;
}) {
  const t = messages(state.locale),
    current = workbook
      ? editor.currentState.workbookProtection
      : editor.currentState.protection;
  const [password, setPassword] = useState("");
  const [confirmation, setConfirmation] = useState("");
  return (
    <section aria-label={workbook ? t.workbookProtection : t.sheetProtection}>
      <p>
        {workbook
          ? current.protected
            ? t.workbookProtected
            : t.workbookUnprotected
          : current.protected
            ? t.sheetProtected
            : t.sheetUnprotected}
      </p>
      <p>{workbook ? t.workbookProtectionHint : t.protectionHint}</p>
      <form
        onSubmit={(event) => {
          event.preventDefault();
          controller.run(async () => {
            try {
              if (!current.protected && password !== confirmation)
                throw new Error(t.protectionPasswordMismatch);
              await editor.editSheet({
                action: workbook ? "workbookProtection" : "protection",
                enabled: !current.protected,
                password,
              });
            } finally {
              setPassword("");
              setConfirmation("");
            }
          });
        }}
      >
        <fieldset disabled={disabled || !!current.reason}>
          <label>
            {t.protectionPassword}
            <input
              type="password"
              aria-label={t.protectionPassword}
              autoComplete={
                current.protected ? "current-password" : "new-password"
              }
              maxLength={255}
              value={password}
              onChange={(event) => setPassword(event.currentTarget.value)}
            />
          </label>
          {!current.protected && (
            <label>
              {t.protectionConfirm}
              <input
                type="password"
                aria-label={t.protectionConfirm}
                autoComplete="new-password"
                maxLength={255}
                value={confirmation}
                onChange={(event) => setConfirmation(event.currentTarget.value)}
              />
            </label>
          )}
          <button type="submit">
            {workbook
              ? current.protected
                ? t.unprotectWorkbook
                : t.protectWorkbook
              : current.protected
                ? t.unprotectSheet
                : t.protectSheet}
          </button>
        </fieldset>
      </form>
      {current.reason && <p>{current.reason}</p>}
    </section>
  );
}
