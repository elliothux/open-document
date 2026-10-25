import { useState } from "react";
import type { PresentationEditor } from "@open-document/web/presentation-editor";
import type { PptxConnectorEnd } from "@open-document/web/pptx";
import type { EditorController, UiSnapshot } from "./controller.js";
import { messages } from "./messages.js";

export function PptxConnectors({
  controller,
  state,
  editor,
  disabled,
  insert,
}: {
  controller: EditorController;
  state: UiSnapshot;
  editor: PresentationEditor;
  disabled: boolean;
  insert: boolean;
}) {
  const t = messages(state.locale),
    query = editor.query;
  const selected = query.objects.find((o) => o.id === query.selection.object);
  const connector = selected?.connector;
  const [kind, setKind] = useState<
    | "straight"
    | "rightAngle"
    | "elbow"
    | "elbow4"
    | "elbow5"
    | "curved"
    | "curved2"
    | "curved4"
    | "curved5"
  >(!insert && connector?.kind ? connector.kind : "straight");
  const [points, setPoints] = useState<PptxConnectorEnd[]>(
    !insert && connector?.start && connector.end
      ? [connector.start, connector.end]
      : [
          { x: 72, y: 72, target: "", site: 0 },
          { x: 240, y: 180, target: "", site: 0 },
        ],
  );
  if (!insert && !connector) return null;
  const reason = insert ? query.readOnlyReason : connector?.reason;
  return (
    <form
      onSubmit={(event) => {
        event.preventDefault();
        controller.run(() =>
          editor.editObjects({
            action: insert ? "insertConnector" : "connectorEndpoints",
            kind,
            start: points[0]!,
            end: points[1]!,
          }),
        );
      }}
    >
      <fieldset
        disabled={
          disabled ||
          !!reason ||
          (!insert &&
            (query.selection.mode !== "object" ||
              query.selection.objects.length !== 1))
        }
      >
        <legend>{insert ? t.insertConnector : t.connectorEndpoints}</legend>
        <label>
          {t.connectorKind}
          <select
            value={kind}
            onChange={(event) =>
              setKind(
                event.currentTarget.value === "curved"
                  ? "curved"
                  : event.currentTarget.value === "curved2"
                    ? "curved2"
                    : event.currentTarget.value === "curved4"
                      ? "curved4"
                      : event.currentTarget.value === "curved5"
                        ? "curved5"
                        : event.currentTarget.value === "elbow5"
                          ? "elbow5"
                          : event.currentTarget.value === "elbow4"
                            ? "elbow4"
                            : event.currentTarget.value === "rightAngle"
                              ? "rightAngle"
                              : event.currentTarget.value === "elbow"
                                ? "elbow"
                                : "straight",
              )
            }
          >
            <option value="straight">{t.connectorStraight}</option>
            <option value="rightAngle">{t.connectorRightAngle}</option>
            <option value="elbow">{t.connectorElbow}</option>
            <option value="elbow4">{t.connectorElbow4}</option>
            <option value="elbow5">{t.connectorElbow5}</option>
            <option value="curved">{t.connectorCurved}</option>
            <option value="curved2">{t.connectorCurved2}</option>
            <option value="curved4">{t.connectorCurved4}</option>
            <option value="curved5">{t.connectorCurved5}</option>
          </select>
        </label>
        {points.map((point, index) => {
          const target = query.objects.find((o) => o.id === point.target);
          const set = (patch: Partial<PptxConnectorEnd>) =>
            setPoints(
              points.map((p, i) => (i === index ? { ...p, ...patch } : p)),
            );
          return (
            <fieldset key={index}>
              <legend>{index === 0 ? t.connectorStart : t.connectorEnd}</legend>
              <label>
                {t.connectorTarget}
                <select
                  value={point.target}
                  onChange={(event) =>
                    set({ target: event.currentTarget.value, site: 0 })
                  }
                >
                  <option value="">{t.connectorFree}</option>
                  {query.objects
                    .filter(
                      (o) =>
                        o.parent === (insert ? "" : (selected?.parent ?? "")) &&
                        o.id.startsWith(query.selection.slide + "#") &&
                        o.connectionSiteCount > 0 &&
                        !o.connector &&
                        o.kind !== "group" &&
                        o.kind !== "table" &&
                        (!o.readOnlyReason ||
                          o.readOnlyReason === "Group members are read-only" ||
                          o.id === point.target),
                    )
                    .map((o) => (
                      <option key={o.id} value={o.id}>
                        {o.name}
                      </option>
                    ))}
                </select>
              </label>
              <label>
                {t.connectorSite}
                <select
                  disabled={!point.target}
                  value={point.site}
                  onChange={(event) =>
                    set({ site: Number(event.currentTarget.value) })
                  }
                >
                  {(target?.shapeAdjustments.preset === "ellipse"
                    ? [
                        t.connectorTop,
                        t.connectorTopLeft,
                        t.connectorLeft,
                        t.connectorBottomLeft,
                        t.connectorBottom,
                        t.connectorBottomRight,
                        t.connectorRight,
                        t.connectorTopRight,
                      ]
                    : target?.connectionSiteCount === 4
                      ? [
                          t.connectorTop,
                          t.connectorLeft,
                          t.connectorBottom,
                          t.connectorRight,
                        ]
                      : Array.from(
                          { length: target?.connectionSiteCount ?? 0 },
                          (_, site) => `${t.connectorSite} ${site + 1}`,
                        )
                  ).map((label, site) => (
                    <option key={site} value={site}>
                      {label}
                    </option>
                  ))}
                </select>
              </label>
              {(["x", "y"] as const).map((key) => (
                <label key={key}>
                  {key === "x" ? t.objectX : t.objectY}
                  <input
                    type="number"
                    required
                    min={-14400}
                    max={14400}
                    step="any"
                    disabled={!!point.target}
                    value={point[key]}
                    onChange={(event) =>
                      set({ [key]: Number(event.currentTarget.value) })
                    }
                  />
                </label>
              ))}
            </fieldset>
          );
        })}
        <button type="submit">
          {insert ? t.insertConnector : t.applyConnector}
        </button>
      </fieldset>
      {reason && <p role="status">{reason}</p>}
    </form>
  );
}
