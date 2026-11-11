export interface BasicDrawingShape {
  preset: "rect" | "ellipse" | "line" | "polyline";
  fill: string;
  stroke: string;
  lineWidth: number;
  points: [number, number][];
  strokeAlpha: number;
}
