# UI Polish Baseline Performance

Recorded: 2026-07-11
Commit: `f8caa38b4bcd6223c1ad426d6717b2ea3eeca0ff`
Build: Release, unchanged source
Host: MacBook Pro (`Mac16,7`), Apple M4 Pro, 14 cores, 24 GB memory
System: macOS 26.4, Xcode 26.4.1
Display: built-in Liquid Retina XDR, `2056 x 1329` points, 2x scale

## Display Modes

Transition recordings were captured at every available refresh rate for the
current display resolution: 48, 50, 60, and 120 Hz. Standard and Reduce Motion
clips use the filenames defined in the research brief. The current baseline
does not read Reduce Motion, so those clips intentionally show the same motion.

## CPU Samples

Time Profiler was attached to the same collapsed Release process for three
60-second runs per state at 120 Hz. The terminal session remained active while
the existing state file switched between `idle`, `working`, and `attention`.
CPU was sampled once per second with `ps`; averages below are the raw run
results used to calculate each median.

| Visible state | Run | Samples | Minimum | Maximum | Average |
| --- | ---: | ---: | ---: | ---: | ---: |
| Ready | 1 | 64 | 0.000% | 0.600% | 0.072% |
| Ready | 2 | 64 | 0.000% | 0.200% | 0.081% |
| Ready | 3 | 64 | 0.000% | 0.200% | 0.080% |
| Working | 1 | 65 | 9.700% | 16.000% | 12.057% |
| Working | 2 | 66 | 4.400% | 34.900% | 13.395% |
| Working | 3 | 65 | 11.600% | 15.400% | 13.662% |
| Waiting | 1 | 65 | 9.800% | 17.100% | 13.049% |
| Waiting | 2 | 65 | 9.700% | 13.200% | 12.009% |
| Waiting | 3 | 65 | 8.800% | 13.500% | 11.185% |

| Visible state | Median CPU |
| --- | ---: |
| Ready | 0.080% |
| Working | 13.395% |
| Waiting | 12.009% |

The active breathing dot accounts for the large working/waiting difference.
Ready is static. This sprint records that behavior without changing it; the
Rose Three track owns the later comparison and idle-cost gate.

## Baseline Trace Retention

The nine Time Profiler traces and their one-second CSV samples were created
outside Git under `/tmp/ghostnotch-ui-polish-traces/`:

- `baseline-{ready,working,waiting}-{1,2,3}.trace`
- `baseline-{ready,working,waiting}-{1,2,3}.csv`

These traces contained local process diagnostics and were intentionally not
part of the repository. The table above is the durable sanitized summary; the
235 MB temporary trace directory was removed on 2026-07-13 after verification.
