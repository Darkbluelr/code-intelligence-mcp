# Red Baseline Summary

**Date**: 2026-01-11
**Change**: enhance-code-intelligence
**Phase**: OpenSpec Apply - Test Owner

## Test Execution Summary

| Test File | Total | Passed | Failed | Skipped |
|-----------|-------|--------|--------|---------|
| hotspot-analyzer.bats | 13 | 6 | 7 | 0 |
| boundary-detector.bats | 17 | 4 | 13 | 0 |
| intent-analysis.bats | 11 | 5 | 5 | 1 |
| subgraph-retrieval.bats | 14 | 3 | 0 | 11 |
| pattern-learner.bats | 19 | 6 | 5 | 8 |
| data-flow-tracing.bats | 16 | 5 | 1 | 10 |
| incremental-indexing.bats | 16 | 4 | 4 | 8 |
| mcp-contract.bats | 24 | 19 | 2 | 3 |
| feature-toggle.bats | 11 | 3 | 0 | 8 |
| bug-locator.bats | 16 | 15 | 1 | 0 |
| **TOTAL** | **157** | **70** | **38** | **49** |

## Failure Breakdown by AC

### AC-001: Hotspot Algorithm (7 failures)
- HS-002b: --version shows version
- HS-003: default returns Top-20 hotspot files in JSON
- HS-004: custom top_n parameter
- HS-005: hotspot score formula
- HS-OUTPUT-001: JSON output is valid JSON
- HS-OUTPUT-002: output includes file field

### AC-002: Intent Analysis (5 failures)
- IA-001: explicit signal extraction
- IA-002: implicit signal extraction
- IA-003: historical signal extraction
- IA-004: code signal extraction
- IA-AGG-001: 4-dimensional signal aggregation output

### AC-004: Boundary Detection (13 failures)
- BD-002 ~ BD-006b: Library/Generated/User/Config detection
- BD-OUTPUT-001 ~ BD-OUTPUT-003: JSON output format

### AC-005: Pattern Learner (5 failures)
- PL-001 ~ PL-001c: Script existence and basic commands
- PL-PARAM-001, PL-PARAM-003: Parameter support

### AC-006: Data Flow Tracing (1 failure)
- DF-004: --help includes --trace-data-flow description

### AC-007: Incremental Indexing (4 failures)
- II-BASE-001 ~ II-BASE-002: Script existence and basic commands
- II-PARAM-001: --incremental parameter support

### AC-008: MCP Contract (2 failures)
- CT-002: ci_hotspot output format - schema_version
- CT-002b: ci_hotspot output format - hotspots array

### AC-009: Bug Locator Regression (1 failure)
- BL-008: JSON output is valid JSON

## Red Baseline Status

✅ **Red baseline successfully established**

- Total hard failures (excluding skips): **38**
- Tests skipped due to features not implemented: **49**
- Tests passing (existing functionality): **70**

## Notes

1. Most failures are expected as new features (hotspot-analyzer.sh, boundary-detector.sh, pattern-learner.sh, ast-diff.sh) have not been implemented yet
2. Skipped tests use bats `skip` command to indicate features pending implementation
3. bug-locator.bats (AC-009) shows 15/16 passing - existing functionality preserved
4. mcp-contract.bats shows 19/24 passing - basic MCP structure exists

## Next Steps

1. Coder role implements features to turn Red→Green
2. Run `bats tests/*.bats` after implementation
3. All tests should pass (Green baseline)
4. Run `openspec validate enhance-code-intelligence --strict`
