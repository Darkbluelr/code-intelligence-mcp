# Red Baseline Summary

**Change ID**: `optimize-indexing-pipeline-20260117`
**Date**: 2026-01-18
**Test File**: `tests/indexer-scheduler.bats`

## Summary Statistics

- **Total Tests**: 37
- **Passed (via skip)**: 30
- **Failed**: 7
- **Skipped (expected)**: 24

## Expected Failures (Features Not Yet Implemented)

The following tests **correctly demonstrate Red status** because the features are not yet implemented:

### AC-001: Incremental-First Index Path
- IS-001: `--dry-run` parameter not implemented
- IS-001b: `--once` parameter not implemented
- IS-001c: Threshold checking not implemented

### AC-002: Reliable Fallback
- IS-002: Fallback decision logic not implemented
- IS-002b: Cache version mismatch handling not implemented
- IS-002c: File count threshold exceeded not implemented

### AC-003: Offline SCIP Proto Resolution
- IS-003: `--check-proto` parameter not implemented
- IS-003b: Custom proto path not implemented
- IS-003c: Proto error handling not implemented
- IS-003d: Proto version output not implemented

### AC-004: CLI Compatibility
- IS-004c: `--dry-run` not documented in help
- IS-004d: `--once` not documented in help (**FAILED**)
- IS-CLI-001: New CLI options not documented (**FAILED**)

### AC-005: ci_index_status Semantic Alignment
- IS-005: Still routes to indexer.sh instead of embedding.sh (**FAILED**)
- IS-005a: Status output format doesn't match expected (**FAILED**)

### AC-006: Idempotent Operations
- IS-006: Idempotency not verified
- IS-006b: Full rebuild idempotency not verified

### AC-007: Debounce Window
- IS-007: Debounce aggregation not implemented
- IS-007b: Debounce config reading not implemented

### AC-008: Version Stamp
- IS-008: Version stamp update not implemented
- IS-008b: Cache clearing not implemented
- IS-008c: Version comparison not implemented

### AC-009: Feature Toggle
- IS-009: Feature toggle reading not implemented
- IS-009b: Environment variable override not implemented
- IS-009c: Configurable threshold not implemented

### AC-010: Concurrent Write Safety
- IS-010: Test passed (SQLite WAL mode working)
- IS-010b: Test passed (No lock errors)

## Hard Failures (Tests That Actually Failed)

These tests failed because the expected behavior is not implemented:

1. **IS-004b**: `--status` output doesn't contain expected strings
2. **IS-004d**: `--once` not in help output
3. **IS-005**: `ci_index_status` incorrectly routes to `indexer.sh`
4. **IS-005a**: `embedding.sh status` output doesn't match expected format
5. **IS-BOUNDARY-003**: Invalid config not handled gracefully
6. **IS-CLI-001**: New CLI options not documented in help

## Interpretation

The Red baseline is successfully established:

1. **Expected skips**: Features like `--dry-run`, `--once`, and scheduling logic are not yet implemented, so tests skip correctly.

2. **Hard failures**: Tests that check routing and help output fail because the implementation doesn't yet match the design specification.

3. **Passing tests**: Some tests pass because they verify existing behavior (e.g., `--help` shows existing options, concurrent SQLite writes work).

## Traceability

| AC ID | Tests in Red | Status |
|-------|--------------|--------|
| AC-001 | IS-001, IS-001b, IS-001c | Skip (not implemented) |
| AC-002 | IS-002, IS-002b, IS-002c | Skip (not implemented) |
| AC-003 | IS-003, IS-003b, IS-003c, IS-003d | Skip (not implemented) |
| AC-004 | IS-004d, IS-CLI-001 | FAIL (not implemented) |
| AC-005 | IS-005, IS-005a | FAIL (wrong routing) |
| AC-006 | IS-006, IS-006b | Skip (not implemented) |
| AC-007 | IS-007, IS-007b | Skip (not implemented) |
| AC-008 | IS-008, IS-008b, IS-008c | Skip (not implemented) |
| AC-009 | IS-009, IS-009b, IS-009c | Skip (not implemented) |
| AC-010 | - | PASS (existing functionality) |

## Evidence Files

- `test-20260118-135502.log` - Full test output
