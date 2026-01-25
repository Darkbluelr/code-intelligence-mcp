# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.0] - 2026-01-25

### Changed
- **BREAKING**: Renamed index directory from `.ckb/` to `.ci-index/` for better clarity and to avoid confusion with external CKB MCP service
- Updated version to 0.3.0 to reflect the breaking change

### Added
- Automatic runtime migration in embedding.sh that detects and renames existing `.ckb/` directories to `.ci-index/`
- Migration happens automatically when you run ci-search or any embedding-related command
- Bilingual (Chinese/English) migration messages

### Fixed
- Clarified naming convention to distinguish between internal index storage and external MCP services
- Migration now works correctly for both local and global installations

## [0.2.4] - Previous Release

### Features
- Semantic code search with embedding support
- Graph-RAG context retrieval
- Call chain analysis
- Impact analysis
- Bug location assistance
- Multiple MCP tools for code intelligence
