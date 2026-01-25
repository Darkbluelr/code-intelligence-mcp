// file-reader.ts - Mock stub for benchmark testing (m-002)
// Expected file for query: "how to read file"

import * as fs from 'fs';

export interface ReadOptions {
  encoding?: BufferEncoding;
  flag?: string;
}

export class FileReader {
  private basePath: string;

  constructor(basePath: string = '.') {
    this.basePath = basePath;
  }

  async readFile(path: string, options?: ReadOptions): Promise<string> {
    const fullPath = `${this.basePath}/${path}`;
    return fs.promises.readFile(fullPath, options?.encoding || 'utf-8');
  }

  readFileSync(path: string, options?: ReadOptions): string {
    const fullPath = `${this.basePath}/${path}`;
    return fs.readFileSync(fullPath, options?.encoding || 'utf-8');
  }

  async exists(path: string): Promise<boolean> {
    try {
      await fs.promises.access(`${this.basePath}/${path}`);
      return true;
    } catch {
      return false;
    }
  }
}

export function readTextFile(path: string): string {
  return fs.readFileSync(path, 'utf-8');
}

export function readJsonFile<T>(path: string): T {
  const content = readTextFile(path);
  return JSON.parse(content);
}
