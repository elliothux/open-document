import type { ReactNode } from "react";
import type { UiSnapshot } from "./controller.js";
import type { PanelProps } from "./types.js";
export type { PanelProps } from "./types.js";
import { Command, Group } from "./controls.js";
import { messages } from "./messages.js";
export function Navigation({ controller, state, file, disabled }: PanelProps) {
  const t = messages(state.locale);
  const snapshot = file.editor.getSnapshot();
  const page = snapshot.page,
    count = snapshot.pageCount;
  const navigate = (index: number) =>
    controller.run(() => {
      return file.navigate(index);
    });
  return (
    <Group label={t.navigation}>
      <Command
        label={t.previous}
        disabled={disabled || page <= 0}
        action={() => navigate(page - 1)}
      />
      <span>
        {page + 1} / {count}
      </span>
      <Command
        label={t.next}
        disabled={disabled || page + 1 >= count}
        action={() => navigate(page + 1)}
      />
    </Group>
  );
}

export function Zoom({ controller, state, file, disabled }: PanelProps) {
  const t = messages(state.locale);
  return (
    <label className="od-zoom">
      {t.zoom}{" "}
      <select
        aria-label={t.zoom}
        disabled={disabled}
        value={state.document?.zoom ?? 1}
        onChange={(event) =>
          controller.run(() =>
            file.editor.setZoom(Number(event.currentTarget.value)),
          )
        }
      >
        {[0.5, 0.75, 1, 1.25, 1.5, 2].map((zoom) => (
          <option key={zoom} value={zoom}>
            {Math.round(zoom * 100)}%
          </option>
        ))}
      </select>
    </label>
  );
}

export function Details({ state }: { state: UiSnapshot }) {
  const t = messages(state.locale),
    snapshot = state.document;
  const reasons: ReactNode[] = [
    snapshot?.readOnlyReason,
    ...(snapshot?.diagnostics ?? []),
  ].filter(Boolean);
  return reasons.length ? (
    <details>
      <summary>
        {t.diagnostics} ({reasons.length})
      </summary>
      <ul>
        {reasons.map((reason, index) => (
          <li key={index}>{reason}</li>
        ))}
      </ul>
    </details>
  ) : null;
}
