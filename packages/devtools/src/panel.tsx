import { useState, useSyncExternalStore } from "react";
import type { EditorSnapshot } from "@open-document/web-core/editor-state";

export interface DevToolsSource {
  getSnapshot(): EditorSnapshot & { readonly name?: string };
  subscribe(listener: () => void): () => void;
}

export function DevToolsPanel({ source }: { source: DevToolsSource }) {
  const snapshot = useSyncExternalStore(source.subscribe, source.getSnapshot);
  const [query, setQuery] = useState(false);
  const {
    name,
    format,
    documentId,
    revision,
    modified,
    page,
    pageCount,
    selection,
    busy,
    stopped,
    error,
    readOnlyReason,
    diagnostics,
  } = snapshot;
  return (
    <details open>
      <summary>Open Document DevTools</summary>
      <pre aria-label="Editor state">
        {JSON.stringify(
          {
            name,
            format,
            documentId,
            revision,
            modified,
            page,
            pageCount,
            selection,
            busy,
            stopped,
            error,
            readOnlyReason,
            diagnostics,
          },
          null,
          2,
        )}
      </pre>
      <details onToggle={(event) => setQuery(event.currentTarget.open)}>
        <summary>Core query</summary>
        {query && <pre>{JSON.stringify(snapshot.data, null, 2)}</pre>}
      </details>
    </details>
  );
}
