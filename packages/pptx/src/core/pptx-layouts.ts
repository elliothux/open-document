export interface PptxSlideLayouts {
  current: string;
  choices: { id: string; name: string; master: string; masterName: string }[];
  reason: string;
}
