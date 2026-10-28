import type {
  PdfDrawingAnnotation,
  PdfFieldDesign,
  PdfQuery,
  PdfTextSpec,
} from "../core/pdf.js";
import type { Draft } from "./pdf-draft.js";
import type { PdfPropertyInputs } from "./pdf-property-input.js";

function currentPage(state: PdfQuery) {
  const page = state.pages.find((page) => page.id === state.page);
  if (!page) throw new Error("Current PDF page is unavailable");
  return page;
}
function fontFamily(profile: Readonly<Record<string, string>>): string {
  return profile["*"]
    ? "Arial"
    : (Object.keys(profile).find((name) => !name.includes("|")) ?? "Arial");
}

export function imageCropDraft(
  controls: PdfPropertyInputs,
  page: string,
  id: string,
): Draft {
  controls.cropInputs.reset();
  return {
    kind: "imageCrop",
    page,
    id,
    original: "",
    originalSpec: controls.cropInputs.signature,
  };
}

/** Initialize DOM inputs only; the editor queues and owns the returned draft. */
export function textDraft(
  controls: PdfPropertyInputs,
  state: PdfQuery,
  profile: Readonly<Record<string, string>>,
  role: PdfTextSpec["role"],
): Draft {
  const page = currentPage(state),
    bottom = role === "footer" || role === "page-number";
  controls.objectInputs.set({
    placement: {
      x: 20,
      y: bottom ? Math.max(0, page.height - 40) : 20,
      width: Math.max(1, Math.min(200, page.width - 40)),
      height: bottom ? 30 : 60,
      rotation: 0,
    },
    text: "",
    font: fontFamily(profile),
    size: 14,
    color: "000000",
    role,
    foreground: role !== "watermark",
  });
  controls.text.value = role === "page-number" ? "{page}" : "";
  return {
    kind: "newText",
    id: "",
    page: page.id,
    original: "",
    originalSpec: controls.objectInputs.signature,
    role,
    pages: role === "text" ? [page.id] : state.pages.map((page) => page.id),
  };
}

export function drawingDraft(
  controls: PdfPropertyInputs,
  state: PdfQuery,
  kind: PdfDrawingAnnotation["kind"],
  arrow: boolean,
): Draft {
  const page = currentPage(state),
    x = Math.min(20, page.width / 10),
    y = Math.min(20, page.height / 10);
  const width = Math.min(120, page.width - x * 2),
    height = Math.min(60, page.height - y * 2);
  controls.objectInputs.set({
    placement: { x, y, width, height, rotation: 0 },
    text: "",
    font: "",
    size: 14,
    color: "000000",
    role: "text",
    foreground: true,
  });
  controls.objectInputs.inputs.points.value =
    kind === "Line" || kind === "Ink"
      ? `${x + 2},${y + 2},${x + width - 2},${y + height - 2}`
      : "";
  controls.text.value = "";
  return {
    kind: "newDrawing",
    drawingKind: kind,
    arrow,
    page: page.id,
    id: "",
    original: "",
    originalSpec: controls.objectInputs.signature,
  };
}

export function inkDraft(
  controls: PdfPropertyInputs,
  state: PdfQuery,
  signature: boolean,
): Draft {
  const draft = drawingDraft(controls, state, "Ink", false);
  controls.objectInputs.inputs.points.value = "";
  controls.inkInputs.set([], signature);
  return {
    ...draft,
    kind: "newInk",
    originalSpec:
      controls.objectInputs.signature + controls.inkInputs.signatureKey,
  };
}

export function fieldDraft(
  controls: PdfPropertyInputs,
  state: PdfQuery,
  profile: Readonly<Record<string, string>>,
  kind: PdfFieldDesign["kind"],
): Draft {
  const page = currentPage(state),
    x = Math.min(20, page.width / 10),
    y = Math.min(20, page.height / 10);
  let index = 1;
  while (state.fields.some((field) => field.name === `Field${index}`)) index++;
  controls.fieldInputs.reset(kind, `Field${index}`);
  controls.objectInputs.set({
    placement: {
      x,
      y,
      width: Math.min(200, page.width - x * 2),
      height: Math.min(
        kind === "list" || kind === "radio" ? 100 : 30,
        page.height - y * 2,
      ),
      rotation: 0,
    },
    text: "",
    font: fontFamily(profile),
    size: 12,
    color: "000000",
    role: "text",
    foreground: true,
  });
  controls.text.value = "";
  controls.checked.checked = false;
  return {
    kind: "newField",
    id: "",
    page: page.id,
    original: kind === "checkbox" ? false : "",
    originalSpec:
      controls.objectInputs.signature + controls.fieldInputs.signature,
  };
}

export function pageGeometryDraft(
  controls: PdfPropertyInputs,
  state: PdfQuery,
  pageAction: "crop" | "resize" | "scale",
): Draft {
  const page = currentPage(state);
  controls.objectInputs.set({
    placement: {
      x: 0,
      y: 0,
      width: page.width,
      height: page.height,
      rotation: 0,
    },
    text: "",
    font: "",
    size: 14,
    color: "000000",
    role: "text",
    foreground: true,
  });
  controls.text.value = "";
  return {
    kind: "pageGeometry",
    pageAction,
    page: page.id,
    id: "",
    original: "",
    originalSpec: controls.objectInputs.signature,
  };
}
