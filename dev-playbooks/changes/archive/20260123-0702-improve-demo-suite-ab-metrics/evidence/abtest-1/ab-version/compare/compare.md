# demo-suite compare (ab-version)

## Run
- run_id: abtest-1
- generated_at: 2026-01-23T11:11:34Z
- status: success
- overall_verdict: no_change

## Thresholds
- source: builtin
- path: (builtin)
- sha256: f769b827475baf683c81d63110ef3c0be9e062149208bbe796daf180c42bb098

## Inputs
- A: HEAD (3547af120636a4f2fa8635a238dd3cc5994b5321) status=degraded
- B: HEAD~1 (2ff36e5c6febf6be832a8659992a87f767180e87) status=degraded

## Metrics
| path | direction | a | b | delta_abs | tolerance | verdict |
|---|---|---:|---:|---:|---:|---|
| metrics.demo_suite.total_duration_ms | lower | 126 | 63 | -63.0 | 5000 | no_change |

## Reasons
- (none)
