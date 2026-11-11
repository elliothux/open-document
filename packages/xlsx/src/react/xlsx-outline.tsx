import {
  xlsxWorksheetColumns,
  xlsxWorksheetRows,
} from "@open-document/wasm/engine-source";
import type { PanelProps } from "./panels.js";
import { messages } from "@open-document/ui/messages";
import { Icon } from "@open-document/ui/icons";

export function XlsxOutlinePanel({
  controller,
  state,
  file,
  disabled,
}: PanelProps) {
  if (file.format !== "xlsx") return null;
  const t = messages(state.locale),
    editor = file.editor,
    query = editor.currentState;
  return (
    <fieldset disabled={disabled || !!query.outline.reason}>
      <legend>
        <Icon name="list-nested" />
        {t.outline}
      </legend>
      <p>{t.outlineHelp}</p>
      {(["rows", "columns"] as const).map((axis) => {
        const outline = query.outline[axis],
          range = query.selection.range;
        const first = axis === "rows" ? range.top : range.left,
          last = axis === "rows" ? range.bottom : range.right;
        const seen = new Set<number>();
        const controls = outline.groups.filter((group) => {
          if (seen.has(group.summary)) return false;
          seen.add(group.summary);
          return true;
        });
        return (
          <fieldset key={axis}>
            <legend>
              {axis === "rows" ? t.outlineRows : t.outlineColumns}
            </legend>
            <button
              type="button"
              disabled={last - first >= 4095}
              onClick={() =>
                controller.run(() =>
                  editor.objects.editSheet({
                    action: "group",
                    axis,
                    first,
                    last,
                  }),
                )
              }
            >
              <Icon name="group" />
              {t.groupSelection}
            </button>
            <button
              type="button"
              disabled={last - first >= 4095}
              onClick={() =>
                controller.run(() =>
                  editor.objects.editSheet({
                    action: "ungroup",
                    axis,
                    first,
                    last,
                  }),
                )
              }
            >
              <Icon name="ungroup" />
              {t.ungroupSelection}
            </button>
            <button
              type="button"
              disabled={!outline.groups.length}
              onClick={() =>
                controller.run(() =>
                  editor.objects.editSheet({ action: "clearOutline", axis }),
                )
              }
            >
              <Icon name="eraser" />
              {t.clearOutline}
            </button>
            <label>
              <input
                type="checkbox"
                checked={outline.summaryAfter}
                onChange={(event) => {
                  const after = event.currentTarget.checked;
                  controller.run(() =>
                    editor.objects.editSheet({
                      action: "outlineSummary",
                      axis,
                      after,
                    }),
                  );
                }}
              />
              {t.outlineSummaryAfter}
            </label>
            <ul>
              {controls.map((group) => (
                <li key={`${group.level}:${group.first}:${group.last}`}>
                  <span>
                    {group.first}–{group.last} ({group.level}){" "}
                  </span>
                  <button
                    type="button"
                    aria-label={`${group.collapsed ? t.expandGroup : t.collapseGroup} ${group.first}–${group.last} (${group.level})`}
                    disabled={
                      group.last - group.first >= 4095 ||
                      group.summary < 1 ||
                      group.summary >
                        (axis === "rows"
                          ? xlsxWorksheetRows
                          : xlsxWorksheetColumns) ||
                      outline.groups.some(
                        (outer) =>
                          outer.level < group.level &&
                          outer.collapsed &&
                          outer.first <= group.first &&
                          outer.last >= group.last,
                      )
                    }
                    onClick={() =>
                      controller.run(() =>
                        editor.objects.editSheet({
                          action: "collapseGroup",
                          axis,
                          first: group.first,
                          last: group.last,
                          level: group.level,
                          collapsed: !group.collapsed,
                        }),
                      )
                    }
                  >
                    {group.collapsed ? t.expandGroup : t.collapseGroup}
                  </button>
                </li>
              ))}
            </ul>
          </fieldset>
        );
      })}
      {query.outline.reason && <p role="status">{query.outline.reason}</p>}
    </fieldset>
  );
}
