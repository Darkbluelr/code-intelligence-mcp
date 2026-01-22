import { execFileSync } from 'node:child_process';
import { existsSync, mkdirSync } from 'node:fs';
import { dirname } from 'node:path';

export type SignalType = 'view' | 'edit' | 'ignore';

export interface ContextSignal {
  filePath: string;
  signalType: SignalType;
  timestamp: number;
  weight: number;
}

export interface ContextSignalOptions {
  dbPath?: string;
  decayDays?: number;
}

/**
 * 简单的 Disposable 基类，用于资源管理
 */
abstract class Disposable {
  private _disposed = false;

  dispose(): void {
    if (!this._disposed) {
      this._disposed = true;
      this.onDispose();
    }
  }

  protected abstract onDispose(): void;

  protected checkDisposed(): void {
    if (this._disposed) {
      throw new Error(`${this.constructor.name} has been disposed`);
    }
  }

  get isDisposed(): boolean {
    return this._disposed;
  }
}

export class ContextSignalManager extends Disposable {
  private readonly dbPath: string;
  private readonly decayDays: number;

  constructor(options: ContextSignalOptions = {}) {
    super();
    this.dbPath = options.dbPath ?? '.devbooks/graph.db';
    this.decayDays = options.decayDays ?? 90;
  }

  protected onDispose(): void {
    // 清理资源（如果需要）
    // 当前实现使用 execFileSync，不需要显式清理
  }

  static weightForAction(action: SignalType): number {
    switch (action) {
      case 'edit':
        return 2.0;
      case 'ignore':
        return -0.5;
      case 'view':
      default:
        return 1.5;
    }
  }

  ensureSchema(): void {
    this.checkDisposed();
    const dir = dirname(this.dbPath);
    if (!existsSync(dir)) {
      mkdirSync(dir, { recursive: true });
    }
    this.runSql(`
      CREATE TABLE IF NOT EXISTS user_signals (
        file_path TEXT NOT NULL,
        signal_type TEXT NOT NULL,
        timestamp INTEGER NOT NULL,
        weight REAL NOT NULL,
        PRIMARY KEY (file_path, signal_type, timestamp)
      );
    `);
  }

  recordSignal(filePath: string, signalType: SignalType, timestamp = Math.floor(Date.now() / 1000)): void {
    this.checkDisposed();
    this.validateFilePath(filePath);
    this.validateSignalType(signalType);
    this.validateTimestamp(timestamp);

    const weight = ContextSignalManager.weightForAction(signalType);
    this.ensureSchema();

    // 使用 SQLite 的参数绑定功能（通过 .param 命令）
    // 这比字符串拼接更安全
    const sql = `.param set @filePath '${this.escape(filePath)}'
.param set @signalType '${this.escape(signalType)}'
.param set @timestamp ${timestamp}
.param set @weight ${weight}
INSERT OR REPLACE INTO user_signals (file_path, signal_type, timestamp, weight)
VALUES (@filePath, @signalType, @timestamp, @weight);`;

    this.runSql(sql);
  }

  getSignals(filePath: string): ContextSignal[] {
    this.checkDisposed();
    this.validateFilePath(filePath);
    this.ensureSchema();

    const sql = `.param set @filePath '${this.escape(filePath)}'
SELECT file_path as filePath, signal_type as signalType, timestamp, weight
FROM user_signals WHERE file_path = @filePath;`;

    const output = this.runSqlJson(sql);
    return this.validateSignalArray(output);
  }

  getDecayedScore(filePath: string, nowSeconds = Math.floor(Date.now() / 1000)): number {
    this.checkDisposed();
    this.validateFilePath(filePath);
    this.validateTimestamp(nowSeconds);

    const signals = this.getSignals(filePath);
    let total = 0;
    for (const signal of signals) {
      total += this.decayedWeight(signal.weight, signal.timestamp, nowSeconds);
    }
    return total;
  }

  cleanupExpired(nowSeconds = Math.floor(Date.now() / 1000)): void {
    this.checkDisposed();
    this.validateTimestamp(nowSeconds);

    const cutoff = nowSeconds - this.decayDays * 86400;
    this.ensureSchema();

    const sql = `.param set @cutoff ${cutoff}
DELETE FROM user_signals WHERE timestamp < @cutoff;`;

    this.runSql(sql);
  }

  private decayedWeight(weight: number, timestamp: number, nowSeconds: number): number {
    const ageDays = Math.floor((nowSeconds - timestamp) / 86400);
    if (ageDays >= this.decayDays) {
      return 0;
    }
    const ratio = 1 - ageDays / this.decayDays;
    return weight * ratio;
  }

  private validateFilePath(filePath: string): void {
    if (!filePath || typeof filePath !== 'string') {
      throw new Error('Invalid file path: must be a non-empty string');
    }
    // 防止路径遍历攻击
    if (filePath.includes('\0') || filePath.includes('\n') || filePath.includes('\r')) {
      throw new Error('Invalid file path: contains illegal characters');
    }
  }

  private validateSignalType(signalType: SignalType): void {
    const validTypes: SignalType[] = ['view', 'edit', 'ignore'];
    if (!validTypes.includes(signalType)) {
      throw new Error(`Invalid signal type: ${signalType}. Must be one of: ${validTypes.join(', ')}`);
    }
  }

  private validateTimestamp(timestamp: number): void {
    if (!Number.isInteger(timestamp) || timestamp < 0) {
      throw new Error('Invalid timestamp: must be a non-negative integer');
    }
    // 防止未来时间戳（允许 1 小时的时钟偏差）
    const maxTimestamp = Math.floor(Date.now() / 1000) + 3600;
    if (timestamp > maxTimestamp) {
      throw new Error('Invalid timestamp: cannot be in the future');
    }
  }

  // M-001 fix: Stricter type guard for unvalidated signal objects
  private isUnvalidatedSignal(value: unknown): value is {
    filePath: unknown;
    signalType: unknown;
    timestamp: unknown;
    weight: unknown;
  } {
    return (
      typeof value === 'object' &&
      value !== null &&
      'filePath' in value &&
      'signalType' in value &&
      'timestamp' in value &&
      'weight' in value
    );
  }

  private validateSignalArray(data: unknown): ContextSignal[] {
    if (!Array.isArray(data)) {
      throw new Error('Invalid signal data: expected array');
    }

    return data.map((item, index) => {
      // M-001 fix: Use type guard instead of loose type assertion
      if (!this.isUnvalidatedSignal(item)) {
        throw new Error(`Invalid signal at index ${index}: missing required fields`);
      }

      const signal = item;

      if (typeof signal.filePath !== 'string') {
        throw new Error(`Invalid signal at index ${index}: filePath must be a string`);
      }

      const validTypes: SignalType[] = ['view', 'edit', 'ignore'];
      if (!validTypes.includes(signal.signalType as SignalType)) {
        throw new Error(`Invalid signal at index ${index}: invalid signalType`);
      }

      if (typeof signal.timestamp !== 'number' || !Number.isInteger(signal.timestamp)) {
        throw new Error(`Invalid signal at index ${index}: timestamp must be an integer`);
      }

      if (typeof signal.weight !== 'number') {
        throw new Error(`Invalid signal at index ${index}: weight must be a number`);
      }

      // 类型已验证，安全转换
      return {
        filePath: signal.filePath,
        signalType: signal.signalType as SignalType,
        timestamp: signal.timestamp,
        weight: signal.weight,
      };
    });
  }

  private runSql(sql: string): void {
    this.checkDisposed();
    execFileSync('sqlite3', [this.dbPath, sql], { stdio: 'ignore' });
  }

  private runSqlJson(sql: string): unknown {
    this.checkDisposed();
    const output = execFileSync('sqlite3', ['-json', this.dbPath, sql], { encoding: 'utf8' }).trim();
    if (!output) {
      return [];
    }
    try {
      return JSON.parse(output);
    } catch (error) {
      throw new Error(`Failed to parse SQL JSON output: ${error instanceof Error ? error.message : String(error)}`);
    }
  }

  private escape(value: string): string {
    // SQLite 字符串转义：单引号替换为两个单引号
    // 同时防止其他潜在的注入向量
    return value
      .replace(/'/g, "''")
      .replace(/\\/g, '\\\\')
      .replace(/\0/g, '\\0')
      .replace(/\n/g, '\\n')
      .replace(/\r/g, '\\r');
  }
}
