import { create } from "zustand";

interface DrawingData {
  points: { x: number; y: number }[];
  color: string;
  width: number;
}

interface BlackboardState {
  drawingData: DrawingData[];
  setDrawingData: (data: DrawingData[]) => void;
  addStroke: (stroke: DrawingData) => void;
  clearDrawing: () => void;
  loadSavedWhiteboard: (data: DrawingData[]) => void;
}

export const useBlackboardStore = create<BlackboardState>((set) => ({
  drawingData: [],
  setDrawingData: (data) => set({ drawingData: data }),
  addStroke: (stroke) =>
    set((state) => ({
      drawingData: [...state.drawingData, stroke],
    })),
  clearDrawing: () => set({ drawingData: [] }),
  loadSavedWhiteboard: (data) => set({ drawingData: data }),
}));
