/**
 * AST Delta - TypeScript tree-sitter 解析薄壳
 * 版本: 1.0
 *
 * 提供基于 tree-sitter 的增量 AST 解析功能，支持：
 * - 解析 TypeScript/JavaScript 源代码为 AST 节点树
 * - 计算两棵 AST 树之间的差异（增加、删除、修改）
 * - 序列化/反序列化 AST 节点
 *
 * 覆盖 AC-F01: AST Delta 增量索引：单文件更新 P95 < 100ms（±20%）
 *
 * @module ast-delta
 */

// AST 节点结构
export interface AstNode {
  /** 唯一标识：file_path:node_type:start_line */
  id: string;
  /** 节点类型：function_declaration, class_declaration 等 */
  type: string;
  /** 节点名称（如有） */
  name?: string;
  /** 起始行号 */
  startLine: number;
  /** 结束行号 */
  endLine: number;
  /** 子节点列表 */
  children: AstNode[];
}

// AST 差异结构
export interface AstDelta {
  /** 新增的节点 */
  added: AstNode[];
  /** 删除的节点 */
  removed: AstNode[];
  /** 修改的节点对 */
  modified: Array<{ old: AstNode; new: AstNode }>;
}

// 解析结果
export interface ParseResult {
  success: boolean;
  ast?: AstNode;
  error?: string;
  parseTimeMs?: number;
}

// 解析配置
export interface ParseConfig {
  /** 文件路径，用于生成节点 ID */
  filePath?: string;
  /** 是否包含所有节点（默认只包含定义节点） */
  includeAllNodes?: boolean;
}

// 感兴趣的节点类型（定义类节点）
const DEFINITION_NODE_TYPES = new Set([
  // TypeScript/JavaScript
  'function_declaration',
  'function_expression',
  'arrow_function',
  'method_definition',
  'class_declaration',
  'interface_declaration',
  'type_alias_declaration',
  'enum_declaration',
  'variable_declaration',
  'lexical_declaration',
  'export_statement',
  'import_statement',
  // 方法和属性
  'public_field_definition',
  'property_signature',
  'method_signature',
  // 通用
  'function',
  'class',
  'method',
]);

// 用于提取名称的节点类型
const NAME_EXTRACTORS: Record<string, string[]> = {
  function_declaration: ['name', 'identifier'],
  function_expression: ['name', 'identifier'],
  class_declaration: ['name', 'identifier'],
  interface_declaration: ['name', 'identifier'],
  type_alias_declaration: ['name', 'identifier'],
  enum_declaration: ['name', 'identifier'],
  method_definition: ['name', 'property_identifier'],
  variable_declaration: ['name', 'identifier'],
  lexical_declaration: ['name', 'identifier'],
};

// tree-sitter 类型定义（动态加载）
interface TreeSitterNode {
  type: string;
  text: string;
  startPosition: { row: number; column: number };
  endPosition: { row: number; column: number };
  childCount: number;
  children: TreeSitterNode[];
  namedChildCount: number;
  namedChildren: TreeSitterNode[];
  childForFieldName(name: string): TreeSitterNode | null;
}

interface TreeSitterTree {
  rootNode: TreeSitterNode;
}

interface TreeSitterParser {
  setLanguage(language: unknown): void;
  parse(input: string): TreeSitterTree;
}

// 缓存 tree-sitter 实例
let cachedParser: TreeSitterParser | null = null;
let treeSitterAvailable: boolean | null = null;

/**
 * 检查 tree-sitter 是否可用
 */
export function isTreeSitterAvailable(): boolean {
  if (treeSitterAvailable !== null) {
    return treeSitterAvailable;
  }

  // 检查环境变量强制禁用
  if (process.env.DISABLE_TREE_SITTER === 'true') {
    treeSitterAvailable = false;
    return false;
  }

  try {
    // 尝试加载 tree-sitter
    require.resolve('tree-sitter');
    require.resolve('tree-sitter-typescript');
    treeSitterAvailable = true;
    return true;
  } catch {
    treeSitterAvailable = false;
    return false;
  }
}

/**
 * 获取或创建 tree-sitter 解析器
 */
function getParser(): TreeSitterParser | null {
  if (cachedParser) {
    return cachedParser;
  }

  if (!isTreeSitterAvailable()) {
    return null;
  }

  try {
    // 动态加载 tree-sitter
    // eslint-disable-next-line @typescript-eslint/no-var-requires
    const Parser = require('tree-sitter');
    // eslint-disable-next-line @typescript-eslint/no-var-requires
    const TypeScript = require('tree-sitter-typescript').typescript;

    const parser = new Parser();
    parser.setLanguage(TypeScript);
    cachedParser = parser;
    return parser;
  } catch (error) {
    console.error('[ast-delta] Failed to load tree-sitter:', error);
    treeSitterAvailable = false;
    return null;
  }
}

/**
 * 从 tree-sitter 节点提取名称
 */
function extractNodeName(node: TreeSitterNode): string | undefined {
  const extractors = NAME_EXTRACTORS[node.type];
  if (!extractors) {
    return undefined;
  }

  // 尝试从字段提取
  for (const fieldName of extractors) {
    const child = node.childForFieldName(fieldName);
    if (child) {
      return child.text;
    }
  }

  // 尝试从命名子节点提取
  for (const child of node.namedChildren) {
    if (child.type === 'identifier' || child.type === 'property_identifier') {
      return child.text;
    }
  }

  return undefined;
}

/**
 * 将 tree-sitter 节点转换为 AstNode
 */
function convertNode(
  node: TreeSitterNode,
  filePath: string,
  includeAllNodes: boolean
): AstNode | null {
  const isDefinition = DEFINITION_NODE_TYPES.has(node.type);

  // 如果不是定义节点且不包含所有节点，跳过
  if (!isDefinition && !includeAllNodes) {
    // 但仍然递归处理子节点
    const children: AstNode[] = [];
    for (const child of node.namedChildren) {
      const converted = convertNode(child, filePath, includeAllNodes);
      if (converted) {
        children.push(converted);
      }
    }
    // 如果有子节点，返回虚拟容器
    if (children.length > 0) {
      return {
        id: `${filePath}:container:${node.startPosition.row + 1}`,
        type: 'container',
        startLine: node.startPosition.row + 1,
        endLine: node.endPosition.row + 1,
        children,
      };
    }
    return null;
  }

  const startLine = node.startPosition.row + 1; // tree-sitter 使用 0-based 行号
  const endLine = node.endPosition.row + 1;
  const id = `${filePath}:${node.type}:${startLine}`;
  const name = extractNodeName(node);

  // 递归处理子节点
  const children: AstNode[] = [];
  for (const child of node.namedChildren) {
    const converted = convertNode(child, filePath, includeAllNodes);
    if (converted) {
      children.push(converted);
    }
  }

  return {
    id,
    type: node.type,
    name,
    startLine,
    endLine,
    children,
  };
}

/**
 * 使用正则表达式进行降级解析
 * 当 tree-sitter 不可用时使用
 */
function parseWithRegex(code: string, filePath: string): AstNode {
  const lines = code.split('\n');
  const children: AstNode[] = [];

  // 匹配函数声明
  const funcRegex =
    /^(?:export\s+)?(?:async\s+)?function\s+(\w+)\s*\(/gm;
  // 匹配类声明
  const classRegex =
    /^(?:export\s+)?(?:abstract\s+)?class\s+(\w+)/gm;
  // 匹配接口声明
  const interfaceRegex =
    /^(?:export\s+)?interface\s+(\w+)/gm;
  // 匹配类型别名
  const typeRegex =
    /^(?:export\s+)?type\s+(\w+)/gm;
  // 匹配箭头函数
  const arrowFuncRegex =
    /^(?:export\s+)?(?:const|let|var)\s+(\w+)\s*=\s*(?:async\s+)?(?:\([^)]*\)|[^=])\s*=>/gm;

  // 提取函数
  let match;
  while ((match = funcRegex.exec(code)) !== null) {
    const lineNum = code.substring(0, match.index).split('\n').length;
    children.push({
      id: `${filePath}:function_declaration:${lineNum}`,
      type: 'function_declaration',
      name: match[1],
      startLine: lineNum,
      endLine: lineNum, // 简化：假设单行
      children: [],
    });
  }

  // 提取类
  while ((match = classRegex.exec(code)) !== null) {
    const lineNum = code.substring(0, match.index).split('\n').length;
    children.push({
      id: `${filePath}:class_declaration:${lineNum}`,
      type: 'class_declaration',
      name: match[1],
      startLine: lineNum,
      endLine: lineNum,
      children: [],
    });
  }

  // 提取接口
  while ((match = interfaceRegex.exec(code)) !== null) {
    const lineNum = code.substring(0, match.index).split('\n').length;
    children.push({
      id: `${filePath}:interface_declaration:${lineNum}`,
      type: 'interface_declaration',
      name: match[1],
      startLine: lineNum,
      endLine: lineNum,
      children: [],
    });
  }

  // 提取类型别名
  while ((match = typeRegex.exec(code)) !== null) {
    const lineNum = code.substring(0, match.index).split('\n').length;
    children.push({
      id: `${filePath}:type_alias_declaration:${lineNum}`,
      type: 'type_alias_declaration',
      name: match[1],
      startLine: lineNum,
      endLine: lineNum,
      children: [],
    });
  }

  // 提取箭头函数
  while ((match = arrowFuncRegex.exec(code)) !== null) {
    const lineNum = code.substring(0, match.index).split('\n').length;
    children.push({
      id: `${filePath}:arrow_function:${lineNum}`,
      type: 'arrow_function',
      name: match[1],
      startLine: lineNum,
      endLine: lineNum,
      children: [],
    });
  }

  // 按行号排序
  children.sort((a, b) => a.startLine - b.startLine);

  return {
    id: `${filePath}:program:1`,
    type: 'program',
    startLine: 1,
    endLine: lines.length,
    children,
  };
}

/**
 * 解析 TypeScript/JavaScript 代码为 AST
 *
 * @param code - 源代码字符串
 * @param config - 解析配置
 * @returns AST 根节点
 */
export function parseTypeScript(
  code: string,
  config: ParseConfig = {}
): AstNode {
  const filePath = config.filePath || 'unknown';
  const includeAllNodes = config.includeAllNodes || false;

  // 检查是否强制使用 SCIP/regex 降级
  if (process.env.FORCE_SCIP_FALLBACK === 'true') {
    return parseWithRegex(code, filePath);
  }

  const parser = getParser();
  if (!parser) {
    // tree-sitter 不可用，使用正则降级
    return parseWithRegex(code, filePath);
  }

  try {
    const tree = parser.parse(code);
    const rootNode = tree.rootNode;

    // 转换根节点
    const converted = convertNode(rootNode, filePath, includeAllNodes);
    if (converted) {
      return converted;
    }

    // 返回空的程序节点
    return {
      id: `${filePath}:program:1`,
      type: 'program',
      startLine: 1,
      endLine: code.split('\n').length,
      children: [],
    };
  } catch (error) {
    console.error('[ast-delta] Parse error, falling back to regex:', error);
    return parseWithRegex(code, filePath);
  }
}

/**
 * 扁平化 AST 节点树为节点映射
 */
function flattenNodes(node: AstNode, map: Map<string, AstNode>): void {
  // 跳过容器节点
  if (node.type !== 'container') {
    map.set(node.id, node);
  }
  for (const child of node.children) {
    flattenNodes(child, map);
  }
}

/**
 * 计算两棵 AST 树的节点签名（用于比较）
 */
function getNodeSignature(node: AstNode): string {
  return JSON.stringify({
    type: node.type,
    name: node.name,
    startLine: node.startLine,
    endLine: node.endLine,
    childCount: node.children.length,
  });
}

/**
 * 计算两棵 AST 树之间的差异
 *
 * @param oldAst - 旧 AST 树
 * @param newAst - 新 AST 树
 * @returns AST 差异对象
 */
export function computeDelta(oldAst: AstNode, newAst: AstNode): AstDelta {
  const delta: AstDelta = {
    added: [],
    removed: [],
    modified: [],
  };

  // 扁平化两棵树
  const oldNodes = new Map<string, AstNode>();
  const newNodes = new Map<string, AstNode>();

  flattenNodes(oldAst, oldNodes);
  flattenNodes(newAst, newNodes);

  // 创建基于名称+类型的索引，用于检测修改
  const oldByNameType = new Map<string, AstNode>();
  const newByNameType = new Map<string, AstNode>();

  for (const node of oldNodes.values()) {
    if (node.name) {
      const key = `${node.type}:${node.name}`;
      oldByNameType.set(key, node);
    }
  }

  for (const node of newNodes.values()) {
    if (node.name) {
      const key = `${node.type}:${node.name}`;
      newByNameType.set(key, node);
    }
  }

  // 查找删除和修改的节点
  for (const [key, oldNode] of oldByNameType) {
    const newNode = newByNameType.get(key);
    if (!newNode) {
      // 节点被删除
      delta.removed.push(oldNode);
    } else if (getNodeSignature(oldNode) !== getNodeSignature(newNode)) {
      // 节点被修改
      delta.modified.push({ old: oldNode, new: newNode });
    }
  }

  // 查找新增的节点
  for (const [key, newNode] of newByNameType) {
    if (!oldByNameType.has(key)) {
      delta.added.push(newNode);
    }
  }

  // 处理匿名节点（没有名称的节点）
  // 使用 ID 进行精确匹配
  for (const [id, oldNode] of oldNodes) {
    if (!oldNode.name && !newNodes.has(id)) {
      // 检查是否已经通过名称匹配处理过
      const alreadyRemoved = delta.removed.some((n) => n.id === id);
      if (!alreadyRemoved) {
        delta.removed.push(oldNode);
      }
    }
  }

  for (const [id, newNode] of newNodes) {
    if (!newNode.name && !oldNodes.has(id)) {
      const alreadyAdded = delta.added.some((n) => n.id === id);
      if (!alreadyAdded) {
        delta.added.push(newNode);
      }
    }
  }

  return delta;
}

/**
 * 序列化 AST 节点为 JSON 字符串
 *
 * @param ast - AST 节点
 * @returns JSON 字符串
 */
export function serializeAst(ast: AstNode): string {
  return JSON.stringify(ast, null, 2);
}

/**
 * 反序列化 JSON 字符串为 AST 节点
 *
 * @param json - JSON 字符串
 * @returns AST 节点
 */
export function deserializeAst(json: string): AstNode {
  return JSON.parse(json) as AstNode;
}

/**
 * 使用 tree-sitter 解析文件并返回详细结果
 *
 * @param code - 源代码
 * @param config - 解析配置
 * @returns 解析结果
 */
export function parseWithResult(
  code: string,
  config: ParseConfig = {}
): ParseResult {
  const startTime = Date.now();

  try {
    const ast = parseTypeScript(code, config);
    const parseTimeMs = Date.now() - startTime;

    return {
      success: true,
      ast,
      parseTimeMs,
    };
  } catch (error) {
    const parseTimeMs = Date.now() - startTime;
    return {
      success: false,
      error: error instanceof Error ? error.message : String(error),
      parseTimeMs,
    };
  }
}

/**
 * 收集 AST 中的所有符号
 *
 * @param ast - AST 根节点
 * @returns 符号列表
 */
export function collectSymbols(
  ast: AstNode
): Array<{ name: string; type: string; startLine: number; endLine: number }> {
  const symbols: Array<{
    name: string;
    type: string;
    startLine: number;
    endLine: number;
  }> = [];

  function collect(node: AstNode): void {
    if (node.name && DEFINITION_NODE_TYPES.has(node.type)) {
      symbols.push({
        name: node.name,
        type: node.type,
        startLine: node.startLine,
        endLine: node.endLine,
      });
    }
    for (const child of node.children) {
      collect(child);
    }
  }

  collect(ast);
  return symbols;
}

/**
 * 生成 AST 节点的唯一 ID
 *
 * @param filePath - 文件路径
 * @param nodeType - 节点类型
 * @param startLine - 起始行号
 * @returns 唯一 ID
 */
export function generateNodeId(
  filePath: string,
  nodeType: string,
  startLine: number
): string {
  return `${filePath}:${nodeType}:${startLine}`;
}

// 导出降级解析函数供测试使用
export { parseWithRegex as parseWithRegexFallback };
