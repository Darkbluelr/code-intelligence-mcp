export function loopA(count: number): number {
  if (count <= 0) {
    return 0;
  }
  return loopB(count - 1) + 1;
}

export function loopB(count: number): number {
  if (count <= 0) {
    return 0;
  }
  return loopA(count - 1) + 1;
}
