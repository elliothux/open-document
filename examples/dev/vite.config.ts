import { fileURLToPath } from "node:url";
import { defineConfig } from "vite";
import react from "@vitejs/plugin-react-swc";
import tailwindcss from "@tailwindcss/vite";

const path = (relative: string) =>
  fileURLToPath(new URL(relative, import.meta.url));

export default defineConfig({
  root: path("./"),
  plugins: [react(), tailwindcss()],
  resolve: {
    dedupe: ["react", "react-dom"],
    alias: [
      {
        find: /^@open-document\/wasm\/engine\.wasm(\?.*)?$/,
        replacement: `${path("../../packages/wasm/dist/engine.wasm")}$1`,
      },
      {
        find: /^@open-document\/web\/worker(\?.*)?$/,
        replacement: `${path("../../packages/web/src/worker.ts")}$1`,
      },
      {
        find: "@open-document/devtools",
        replacement: path("../../packages/devtools/src/index.ts"),
      },
      {
        find: "@open-document/ui",
        replacement: path("../../packages/ui/src/index.ts"),
      },
      {
        find: "@open-document/web",
        replacement: path("../../packages/web/src"),
      },
      {
        find: "@open-document/wasm",
        replacement: path("../../packages/wasm/src"),
      },
      {
        find: /^\.\.\/dist\/styles\.css$/,
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
