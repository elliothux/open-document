import { fileURLToPath } from "node:url";
import { defineConfig } from "vite";
import react from "@vitejs/plugin-react-swc";
import tailwindcss from "@tailwindcss/vite";
const path = (relative: string) =>
  fileURLToPath(new URL(relative, import.meta.url));
const domains = ["docx", "xlsx", "pptx", "pdf"];
export default defineConfig({
  root: path("./"),
  plugins: [react(), tailwindcss()],
  resolve: {
    dedupe: [
      "react",
      "react-dom",
      "@open-document/wasm",
      "@open-document/web-core",
      "@open-document/ui",
    ],
    alias: [
      {
        find: /^@open-document\/wasm\/engine\.wasm(\?.*)?$/,
        replacement: `${path("../../packages/wasm/dist/engine.wasm")}$1`,
      },
      {
        find: "@open-document/wasm/engine-source",
        replacement: path("../../packages/wasm/dist/engine-source.js"),
      },
      ...domains.flatMap((domain) => [
        {
          find: new RegExp(`^@open-document/${domain}/worker(\\?.*)?$`),
          replacement: `${path(`../../packages/${domain}/src/worker/index.ts`)}$1`,
        },
        {
          find: new RegExp(`^@open-document/${domain}/react$`),
          replacement: path(`../../packages/${domain}/src/react/index.tsx`),
        },
        {
          find: new RegExp(`^@open-document/${domain}/core$`),
          replacement: path(`../../packages/${domain}/src/core/index.ts`),
        },
        {
          find: new RegExp(`^@open-document/${domain}/web$`),
          replacement: path(`../../packages/${domain}/src/web/index.ts`),
        },
        {
          find: `@open-document/${domain}/`,
          replacement: `${path(`../../packages/${domain}/src/`)}`,
        },
      ]),
      ...["ui", "wasm", "web-core", "devtools"].flatMap((name) => [
        {
          find: new RegExp(`^@open-document/${name}$`),
          replacement: path(`../../packages/${name}/src/index.ts`),
        },
        {
          find: `@open-document/${name}/`,
          replacement: `${path(`../../packages/${name}/src/`)}`,
        },
      ]),
      {
        find: /^\.\.\/dist\/styles\.js$/,
        replacement: `${path("../../packages/ui/src/styles/ui.css")}?inline`,
      },
    ],
  },
  worker: { format: "es" },
  server: {
    host: "127.0.0.1",
    port: 4173,
    strictPort: true,
    fs: {
      allow: [
        path("../../packages"),
        path("../../examples"),
        path("../../node_modules"),
      ],
    },
  },
  build: { outDir: "dist" },
});
