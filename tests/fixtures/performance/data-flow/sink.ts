import { step1 } from "./transform";

export function sink(): string {
  const value = step1();
  return value;
}

export function entry(): string {
  return sink();
}
