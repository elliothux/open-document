import { readFile, writeFile } from "node:fs/promises";
import { loadEngine } from "@open-document/wasm";
import { openDocx } from "@open-document/docx/core";

const [input, output] = process.argv.slice(2);
if (!input || !output)
  throw new Error("Usage: node headless-node.mjs input.docx output.docx");

const wasm = await readFile(
  new URL(import.meta.resolve("@open-document/wasm/docx.wasm")),
);
const session = openDocx(await loadEngine(wasm));
try {
  const opened = session.execute({
    operation: "openDocx",
    bytes: await readFile(input),
    budget: session.defaultBudget(),
  });
  const paragraph = session.execute({ operation: "flow" }).paragraphs[0];
  if (!paragraph) throw new Error("The document has no body paragraph");
  const position = { paragraph: paragraph.id, offset: 0, affinity: "after" };
  session.execute({
    operation: "replaceRange",
    revision: opened.revision,
    selection: { anchor: position, focus: position },
    text: "Reviewed: ",
  });
  await writeFile(output, session.execute({ operation: "saveDocx" }), {
    flag: "wx",
  });
} finally {
  session.close();
}
