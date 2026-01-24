#!/usr/bin/env node
/**
 * postinstall.js - Post-installation script for code-intelligence-mcp
 *
 * This script runs after npm install and provides helpful setup instructions.
 * Uses console.error to ensure output is visible during global installs.
 */

// Use console.error to ensure output is visible during npm install -g
const log = console.error;

log('\n📦 Code Intelligence MCP Server 安装完成！');
log('   Code Intelligence MCP Server installed successfully!\n');

log('🚀 快速开始 / Quick Start:');
log('   1. 添加到 MCP 客户端配置 / Add to your MCP client config');
log('   2. 运行 ci-setup-hook 启用自动上下文注入 / Run ci-setup-hook for auto context injection\n');

log('💡 可选功能 / Optional Features:');
log('   • 自动上下文注入 / Auto Context Injection:');
log('     $ ci-setup-hook\n');

log('📚 文档 / Documentation:');
log('   • README: https://github.com/Darkbluelr/code-intelligence-mcp#readme');
log('   • 技术文档 / Technical Docs: docs/TECHNICAL.md\n');

log('🔧 可用命令 / Available Commands:');
log('   • code-intelligence-mcp  - 启动 MCP 服务器 / Start MCP server');
log('   • ci-search              - 语义代码搜索 / Semantic code search');
log('   • ci-setup-hook          - 安装 Claude Code hook / Install Claude Code hook\n');
