import { useEffect, useState } from "react";
import type { DocumentEditor, DocumentSources } from "../web/editor.js";
import { sourceKinds, type DocxSource } from "../web/foundation.js";
import type { EditorController, UiSnapshot } from "./context.js";
import { messages } from "@open-document/ui/messages";
import { DocxBibliography } from "./docx-bibliography.js";

function sourceValue(
  form: HTMLFormElement,
  previous?: { tag: string; author: string },
): DocxSource {
  const data = new FormData(form);
  const text = (name: string) => String(data.get(name) ?? "");
  const kind = sourceKinds.find((kind) => kind === text("kind"));
  if (!kind) throw new Error("Invalid source type");
  return {
    tag: previous?.tag ?? text("tag"),
    kind,
    author: data.has("author") ? text("author") : (previous?.author ?? ""),
    title: text("title"),
    year: text("year"),
    publisher: text("publisher"),
    url: text("url"),
  };
}

function SourceFields({
  t,
  value,
}: {
  t: ReturnType<typeof messages>;
  value?: DocumentSources["sources"][number];
}) {
  return (
    <>
      <label>
        {t.sourceKind}
        <select name="kind" defaultValue={value?.kind ?? "Book"}>
          {[
            ["Book", t.sourceBook],
            ["JournalArticle", t.sourceJournal],
            ["InternetSite", t.sourceInternet],
            ["Report", t.sourceReport],
            ["Misc", t.sourceMisc],
          ].map(([kind, name]) => (
            <option key={kind} value={kind}>
              {name}
            </option>
          ))}
          {value?.reason &&
            !sourceKinds.some((kind) => kind === value.kind) && (
              <option value={value.kind}>{value.kind}</option>
            )}
        </select>
      </label>
      {(
        [
          ["tag", t.sourceTag, 64],
          ["author", t.sourceAuthor, 1024],
          ["title", t.sourceTitle, 1024],
          ["year", t.sourceYear, 32],
          ["publisher", t.sourcePublisher, 512],
          ["url", t.sourceUrl, 2048],
        ] as const
      ).map(([key, label, maxLength]) => (
        <label key={key}>
          {label}
          <input
            name={key}
            maxLength={maxLength}
            defaultValue={value?.[key] ?? ""}
            required={key === "tag" || key === "title"}
            readOnly={key === "tag" && !!value}
            disabled={key === "author" && !!value?.authorReason}
          />
        </label>
      ))}
      {value?.authorReason && <p>{value.authorReason}</p>}
    </>
  );
}

export function DocxSources({
  controller,
  state,
  editor,
  disabled,
  blocked,
}: {
  controller: EditorController;
  state: UiSnapshot;
  editor: DocumentEditor;
  disabled: boolean;
  blocked: boolean;
}) {
  const t = messages(state.locale),
    snapshot = editor.getSnapshot();
  const [source, setSource] = useState<DocumentSources>();
  useEffect(() => {
    if (blocked) return;
    let active = true;
    controller.run(async () => {
      await editor.whenIdle();
      if (!active) return;
      const value = await editor.sources();
      if (active) setSource(value);
    });
    return () => {
      active = false;
    };
  }, [controller, editor, snapshot.documentId, snapshot.revision, blocked]);
  const stale =
    !source ||
    source.documentId !== snapshot.documentId ||
    source.revision !== snapshot.revision;
  return (
    <section aria-label={t.sources}>
      <h3>{t.sources}</h3>
      <p>{t.sourceHelp}</p>
      <DocxBibliography
        controller={controller}
        editor={editor}
        source={source}
        disabled={disabled || blocked || stale}
        t={t}
      />
      <p>{t.citationHelp}</p>
      <button
        type="button"
        disabled={disabled || blocked || stale}
        onClick={() => controller.run(() => editor.updateCitations())}
      >
        {t.updateCitations}
      </button>
      <form
        aria-label={t.createSource}
        onSubmit={(event) => {
          event.preventDefault();
          const form = event.currentTarget;
          controller.run(async () => {
            await editor.createSource(sourceValue(form));
            form.reset();
          });
        }}
      >
        <fieldset disabled={disabled || blocked || stale}>
          <SourceFields t={t} />
          <button type="submit">{t.createSource}</button>
        </fieldset>
      </form>
      {source?.sources.map((entry) => (
        <form
          aria-label={entry.tag}
          key={JSON.stringify(entry)}
          onSubmit={(event) => {
            event.preventDefault();
            const value = sourceValue(event.currentTarget, entry);
            controller.run(() =>
              editor.editSource(source, { action: "update", source: value }),
            );
          }}
        >
          <fieldset disabled={disabled || blocked || stale || !!entry.reason}>
            <SourceFields t={t} value={entry} />
            <button type="submit">{t.updateSource}</button>
            <button
              type="button"
              disabled={
                !!entry.authorReason ||
                !(entry.author || entry.title) ||
                !snapshot.selection
              }
              onClick={() =>
                controller.run(() => editor.insertCitation(source, entry.tag))
              }
            >
              {t.insertCitation}
            </button>
            <button
              type="button"
              disabled={!!entry.deleteReason}
              title={entry.deleteReason || undefined}
              onClick={() =>
                controller.run(() =>
                  editor.editSource(source, {
                    action: "delete",
                    tag: entry.tag,
                  }),
                )
              }
            >
              {t.deleteSource}
            </button>
          </fieldset>
          {entry.reason && <p>{entry.reason}</p>}
          {entry.deleteReason && <p>{entry.deleteReason}</p>}
        </form>
      ))}
    </section>
  );
}
