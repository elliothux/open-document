import { useEffect, useRef, useState } from "react";
import { messages } from "@open-document/ui/messages";
import type { PanelProps } from "./context.js";
import { Icon } from "@open-document/ui/icons";

const pageSize = 24;

export function PdfSearch({ controller, state, file, disabled }: PanelProps) {
  const t = messages(state.locale);
  const zh = state.locale === "zh-CN";
  const editor = file.editor;
  const data = editor.getSnapshot().data;
  const input = useRef<HTMLInputElement>(null);
  const [search, setSearch] = useState(data.searchQuery);
  const [offset, setOffset] = useState(0);
  const length = data.matches.length;
  const start = Math.min(
    offset,
    Math.max(0, Math.floor((length - 1) / pageSize)) * pageSize,
  );
  const pages = new Map(
    data.query.pages.map((page, index) => [page.id, index + 1]),
  );

  useEffect(() => input.current?.focus(), []);
  useEffect(() => {
    if (data.matchIndex >= 0)
      setOffset(Math.floor(data.matchIndex / pageSize) * pageSize);
  }, [data.matchIndex]);

  return (
    <div className="od-pdf-search">
      <form
        onSubmit={(event) => {
          event.preventDefault();
          setOffset(0);
          controller.run(() => editor.search(search));
        }}
      >
        <label>
          {t.search}
          <input
            type="search"
            value={search}
            ref={input}
            disabled={disabled}
            onChange={(event) => setSearch(event.currentTarget.value)}
          />
        </label>
        <button type="submit" disabled={disabled || !search}>
          <Icon name="search" />
          {t.find}
        </button>
        {data.searching && (
          <button type="button" onClick={() => editor.cancelSearch()}>
            <Icon name="close" />
            {t.cancelSearch}
          </button>
        )}
      </form>
      <p role="status">
        {t.matches}: {length}
        {data.searching ? ` (${t.pages} ${data.searchPage})` : ""}
      </p>
      <div className="od-pdf-action-row">
        <button
          type="button"
          disabled={disabled || !length}
          onClick={() => controller.run(() => editor.nextMatch(-1))}
        >
          <Icon name="search" />
          {t.previousMatch}
        </button>
        <button
          type="button"
          disabled={disabled || !length}
          onClick={() => controller.run(() => editor.nextMatch())}
        >
          <Icon name="search" />
          {t.nextMatch}
        </button>
      </div>
      <ol start={start + 1} aria-label={t.matches}>
        {data.matches.slice(start, start + pageSize).map((match, index) => {
          const position = start + index;
          return (
            <li key={`${match.page}:${match.start}:${match.end}`}>
              <button
                type="button"
                disabled={disabled}
                aria-current={position === data.matchIndex ? "true" : undefined}
                onClick={() => controller.run(() => editor.showMatch(position))}
              >
                {zh
                  ? `第 ${pages.get(match.page)} 页 · 结果 ${position + 1}`
                  : `Page ${pages.get(match.page)} · Result ${position + 1}`}
              </button>
            </li>
          );
        })}
      </ol>
      {length > pageSize && (
        <div className="od-pdf-action-row">
          <button
            type="button"
            disabled={start === 0}
            onClick={() => setOffset(start - pageSize)}
          >
            {zh ? "上一组结果" : "Previous results group"}
          </button>
          <button
            type="button"
            disabled={start + pageSize >= length}
            onClick={() => setOffset(start + pageSize)}
          >
            {zh ? "下一组结果" : "Next results group"}
          </button>
        </div>
      )}
    </div>
  );
}
