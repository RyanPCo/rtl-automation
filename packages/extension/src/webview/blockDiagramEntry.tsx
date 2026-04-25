import { createRoot } from "react-dom/client";
import { BlockDiagramApp } from "./blockDiagramApp.js";

const container = document.getElementById("root");
if (container) {
  createRoot(container).render(<BlockDiagramApp />);
}
