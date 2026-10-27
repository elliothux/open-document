import { createRoot } from "react-dom/client";
import { App } from "./app.js";
import "./style.css";

const root = document.getElementById("root");
if (!root) throw new Error("Preview root is missing");
createRoot(root).render(<App />);
