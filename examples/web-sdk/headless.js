import { DocxWorkerSession } from "@open-document/docx/headless";
import { loadDocumentAssets } from "@open-document/wasm/assets";
import { loadSampleDocument } from "./sample.js";

const form = document.querySelector("form");
const status = document.querySelector("[role=status]");
const link = document.querySelector("#result");
const buttons = form.querySelectorAll("button");
form.addEventListener("submit", async (event) => {
  event.preventDefault();
  buttons.forEach((button) => (button.disabled = true));
  status.textContent = "Editing…";
  if (link.href) URL.revokeObjectURL(link.href);
  link.removeAttribute("href");
  link.hidden = true;
  let session;
  try {
    const file =
      event.submitter?.id === "edit-sample"
        ? await loadSampleDocument()
        : form.elements.document.files[0];
    if (!file) return;
    const { engine, workerUrl } = await loadDocumentAssets(
      "docx",
      new URL("./", import.meta.url),
    );
    session = await DocxWorkerSession.open(engine, workerUrl);
    const opened = await session.execute({
      operation: "openDocx",
      bytes: new Uint8Array(await file.arrayBuffer()),
      budget: await session.defaultBudget(),
    });
    const { paragraphs } = await session.execute({ operation: "flow" });
    const paragraph = paragraphs[0];
    if (!paragraph) throw new Error("The document has no body paragraph");
    const position = { paragraph: paragraph.id, offset: 0, affinity: "after" };
    await session.execute({
      operation: "replaceRange",
      revision: opened.revision,
      selection: { anchor: position, focus: position },
      text: form.elements.prefix.value,
    });
    const bytes = await session.execute({ operation: "saveDocx" });
    link.href = URL.createObjectURL(new Blob([bytes]));
    link.download = `edited-${file.name}`;
    link.hidden = false;
    status.textContent = "The edited DOCX is ready to download.";
  } catch (error) {
    status.textContent = error instanceof Error ? error.message : String(error);
  } finally {
    session?.dispose();
    buttons.forEach((button) => (button.disabled = false));
  }
});
