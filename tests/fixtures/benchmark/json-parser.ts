// json-parser.ts - Mock stub for benchmark testing (m-002)
// Expected file for query: "parse json"

export interface ParseOptions {
  strict?: boolean;
  reviver?: (key: string, value: unknown) => unknown;
}

export interface StringifyOptions {
  indent?: number;
  replacer?: (key: string, value: unknown) => unknown;
}

export class JsonParser {
  private options: ParseOptions;

  constructor(options?: ParseOptions) {
    this.options = options || { strict: true };
  }

  parse<T>(json: string): T {
    try {
      return JSON.parse(json, this.options.reviver);
    } catch (error) {
      if (this.options.strict) {
        throw error;
      }
      return {} as T;
    }
  }

  stringify(value: unknown, options?: StringifyOptions): string {
    return JSON.stringify(
      value,
      options?.replacer,
      options?.indent
    );
  }

  isValid(json: string): boolean {
    try {
      JSON.parse(json);
      return true;
    } catch {
      return false;
    }
  }
}

export function parseJson<T>(json: string): T {
  return JSON.parse(json);
}

export function stringifyJson(value: unknown, indent?: number): string {
  return JSON.stringify(value, null, indent);
}

export function safeParseJson<T>(json: string, defaultValue: T): T {
  try {
    return JSON.parse(json);
  } catch {
    return defaultValue;
  }
}
