#!/usr/bin/env node
/**
 * postinstall.js - Post-installation script for code-intelligence-mcp
 *
 * This script runs after npm install and provides helpful setup instructions.
 */

console.log('\n📦 Code Intelligence MCP Server 安装完成！');
console.log('   Code Intelligence MCP Server installed successfully!\n');

console.log('🚀 快速开始 / Quick Start:');
console.log('   1. 添加到 MCP 客户端配置 / Add to your MCP client config');
console.log('   2. 运行 ci-setup-hook 启用自动上下文注入 / Run ci-setup-hook for auto context injection\n');

console.log('💡 可选功能 / Optional Features:');
console.log('   • 自动上下文注入 / Auto Context Injection:');
console.log('     $ ci-setup-hook\n');

console.log('📚 文档 / Documentation:');
console.log('   • README: https://github.com/Darkbluelr/code-intelligence-mcp#readme');
console.log('   • 技术文档 / Technical Docs: docs/TECHNICAL.md\n');

console.log('🔧 可用命令 / Available Commands:');
console.log('   • code-intelligence-mcp  - 启动 MCP 服务器 / Start MCP server');
console.log('   • ci-search              - 语义代码搜索 / Semantic code search');
console.log('   • ci-setup-hook          - 安装 Claude Code hook / Install Claude Code hook\n');
