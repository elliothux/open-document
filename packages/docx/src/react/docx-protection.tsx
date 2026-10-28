import { useState } from "react";
import type { DocumentEditor, DocumentProtection } from "../web/editor.js";
import type { EditorController, UiSnapshot } from "./context.js";
import { messages } from "@open-document/ui/messages";

export function DocxProtection({
  controller,
  state,
  editor,
  disabled,
}: {
  controller: EditorController;
  state: UiSnapshot;
  editor: DocumentEditor;
  disabled: boolean;
}) {
  const t = messages(state.locale);
  const [source, setSource] = useState<DocumentProtection>();
  const [password, setPassword] = useState("");
  const [confirmation, setConfirmation] = useState("");
  const snapshot = editor.getSnapshot();
  const stale =
    source?.documentId !== snapshot.documentId ||
    source.revision !== snapshot.revision;
  const load = async () => {
    setSource(await editor.documentProtection());
    setPassword("");
    setConfirmation("");
  };
  return (
    <section aria-label={t.documentProtection}>
      <h4>{t.documentProtection}</h4>
      <p>{t.documentProtectionScope}</p>
      <button
        type="button"
        disabled={disabled}
        onClick={() => controller.run(load)}
      >
        {t.loadDocumentProtection}
      </button>
      {source && (
        <form
          onSubmit={(event) => {
            event.preventDefault();
            controller.run(async () => {
              try {
                if (!source.protected && password !== confirmation)
                  throw new Error(t.protectionPasswordMismatch);
                await editor.setDocumentProtection(
                  source,
                  !source.protected,
                  password,
                );
                await load();
              } finally {
                setPassword("");
                setConfirmation("");
              }
            });
          }}
        >
          <p role="status">
            {source.protected ? t.documentProtected : t.documentUnprotected}
          </p>
          {source.reason && <p>{source.reason}</p>}
          <fieldset disabled={disabled || stale || !!source.reason}>
            <label>
              {t.documentProtectionPassword}
              <input
                type="password"
                maxLength={255}
                value={password}
                autoComplete={
                  source.protected ? "current-password" : "new-password"
                }
                required={source.protected && source.passwordRequired}
                onChange={(event) => setPassword(event.currentTarget.value)}
              />
            </label>
            {!source.protected && (
              <label>
                {t.protectionConfirm}
                <input
                  type="password"
                  maxLength={255}
                  value={confirmation}
                  autoComplete="new-password"
                  onChange={(event) =>
                    setConfirmation(event.currentTarget.value)
                  }
                />
              </label>
            )}
            <button type="submit">
              {source.protected ? t.unprotectDocument : t.protectDocument}
            </button>
          </fieldset>
        </form>
      )}
    </section>
  );
}
