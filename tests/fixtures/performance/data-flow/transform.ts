import { startFlow } from "./source";

export function normalize(input: string): string {
  return input.trim();
}

export function step1(): string {
  const data = normalize(startFlow());
  return data;
}
