import { mountEditor } from "@open-document/ui";

export { mountEditor };

const form = document.querySelector("#open-form");
const status = document.querySelector("#host-status");
let mounted;

form.addEventListener("submit", async (event) => {
  event.preventDefault();
  const button = form.querySelector('button[type="submit"]');
  button.disabled = true;
  try {
    const file = document.querySelector("#document").files[0];
    if (!file) return;
    const extension = file.name.split(".").at(-1).toLowerCase();
    const format = ["csv", "tsv"].includes(extension) ? "xlsx" : extension;
    if (!["docx", "xlsx", "pptx", "pdf"].includes(format))
      throw new Error("Choose DOCX, XLSX, CSV, TSV, PPTX or PDF");
    const profile = JSON.parse(document.querySelector("#profile").value);
    if (
      !profile ||
      Array.isArray(profile) ||
      typeof profile !== "object" ||
      Object.values(profile).some((value) => typeof value !== "string")
    )
      throw new Error("Font profile must be an object of string values");
    const directory = document.querySelector("#host-save").checked
      ? await window.showDirectoryPicker({ mode: "readwrite" })
      : undefined;
    if (mounted && !(await mounted.close())) return;
    mounted = undefined;
    const fonts = await Promise.all(
      Array.from(document.querySelector("#fonts").files, async (font) => ({
        identity: font.name.replace(/\.[^.]*$/, ""),
        bytes: new Uint8Array(await font.arrayBuffer()),
      })),
    );
    // Resources are host inputs; the SDK never downloads fonts or uploads document bytes.
    const wasm = await (
      await fetch(new URL("./engine.wasm", import.meta.url))
    ).arrayBuffer();
    const workerUrl = new URL("./worker.js", import.meta.url);
    mounted = await mountEditor(document.querySelector("#editor"), {
      format,
      document: {
        name: file.name,
        bytes: new Uint8Array(await file.arrayBuffer()),
      },
      resources: { wasm, workerUrl, fonts, profile },
      locale: "en-US",
      ...(directory
        ? {
            onSave: async (output) => {
              const handle = await directory.getFileHandle(output.name, {
                create: true,
              });
              const stream = await handle.createWritable();
              try {
                await stream.write(output.bytes);
                await stream.close();
              } catch (error) {
                await stream.abort().catch(() => {});
                throw error;
              }
              status.textContent = `Host saved ${output.name}`;
            },
          }
        : {}),
    });
    status.textContent = directory
      ? "The host confirms saves after closing the file stream."
      : "Saves generate browser downloads.";
  } catch (error) {
    status.textContent = error instanceof Error ? error.message : String(error);
  } finally {
    button.disabled = false;
  }
});

document.querySelector("#close").addEventListener("click", async () => {
  try {
    if (mounted && (await mounted.close())) {
      mounted = undefined;
      status.textContent = "Closed";
    }
  } catch (error) {
    status.textContent = String(error);
  }
});
