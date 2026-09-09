# LensPilot release test matrix

As of 2026-09-09. A = automated check executed locally after this audit's changes; H = historical CI evidence only; D = device/UI execution required, not run here; O = open implementation/evaluation gap. An A row verifies only the assertion named, not the whole user experience. Evidence and priorities: [product audit](product-audit-2026-09-09.md).

| ID | Area / test setup | Expected outcome | Status |
| --- | --- | --- | --- |
| API-01 | Valid text-only creative request with stubbed provider | Valid safe response; server owns provider key | A |
| API-02 | Client includes provider key / unsafe private payload | Rejected before provider use | A |
| API-03 | Missing/wrong phone authorization | Unauthorized, no guidance response | A |
| API-04 | Missing, stale, invalid, repeated signed request | Rejected with classified error | A |
| API-05 | Same socket changes X-Forwarded-For after exhausting quota | Still 429, Retry-After present | A |
| API-06 | New clients exceed bucket cap | Shared overflow; existing quota not evicted | A |
| API-07 | Rate-limit window expires | Requests recover | A |
| API-08 | Missing/old production config and secrets | Readiness fails closed | A |
| API-09 | Oversized request | Rejected within configured bound | A |
| API-10 | Metrics authorization/redaction | Protected; no raw prompts/secrets in output | A |
| API-11 | Provider exhausted credits/error fixture | Classified failure, no raw credentials | A |
| API-12 | Live hosted backend, valid billing, provider latency | Real response and cost within pilot budget | D |
| API-13 | Concurrent instances/restarts and shared mobile credentials | Quotas/replay protection survive chosen production architecture | O |
| CORE-01 | Six deterministic scene benchmarks | Fixture outcomes match expectations | A |
| CORE-02 | Personalization consent, deletion/store sanitization fixtures | Privacy boundaries preserved | A |
| CORE-03 | Online reference parsing/ranking fixtures | Safe query/response contracts | A |
| CORE-04 | Actual compiled TypeScript exports tested against fixtures | Production implementation, not duplicated math, is exercised | O |
| CAL-01 | Current real-capture readiness | Reports 0/24; must not falsely say ready | A |
| CAL-02 | Valid reviewed batch, dry-run/write | Dry-run unchanged; complete batch appended | A |
| CAL-03 | Duplicate IDs, unsafe export, failed manifest validation | Original preserved; temporary manifests cleaned | A |
| CAL-04 | Collect eight scenarios, three reviewed captures each | All 24 satisfy metadata and blind-review requirements | D |
| CAL-05 | Separate matched stock-camera evaluation | Measurable quality preference with uncertainty reported | O |
| AND-01 | Luminance unsigned bytes, padded rows, pixel strides, offsets | Correct dark/balanced/bright category | A |
| AND-02 | Empty/invalid frame | Unknown, no fabricated light assessment | A |
| AND-03 | Scene keyword, multiline, unknown, null and negated request | Supported scene or explicit manual fallback | A |
| AND-04 | More sky, cleaner background, natural tones, less blur | Request-specific idea appears first | A |
| AND-05 | Cycle each scene and reference option | All ideas reachable; no out-of-range access | A |
| AND-06 | Timer 0/3/10s, duplicate start, early/deadline checks | One event at/after deadline, none early | A |
| AND-07 | Timer cancel and lost canCapture guard | No late capture; state clears | A |
| AND-08 | APK build/lint of d63f72f | Previously passed; not evidence for new 0.3.0 changes | H |
| AND-09 | Fresh install; deny/allow/revoke camera permission | Clear recovery, working preview after grant | D |
| AND-10 | Front/back switch; unavailable camera; no flash hardware | No crash, unsupported controls disabled | D |
| AND-11 | Select/replace/remove reference and open/close popup | Full same-phone image, camera flow preserved | D |
| AND-12 | Actual dark/bright scenes, auto-exposure changes | Stable advice after consecutive frames; no flicker | D |
| AND-13 | Capture and repeatedly tap shutter | One saved JPEG per accepted press; useful save errors | D |
| AND-14 | Actual 3s/10s timer; X and Android Back | Correct visible countdown and cancellation | D |
| AND-15 | Background, rotate, lock, open settings/viewer during timer | No unintended later photo | D |
| AND-16 | Storage full, deleted last photo, provider URI expires | Error recoverable; camera still usable | D |
| AND-17 | Share photo, cancel chooser, return | Selected JPEG readable by recipient; app remains usable | D |
| AND-18 | 320dp width, short landscape, 200% font, TalkBack | Controls reachable, labels useful, no overlap | D |
| AND-19 | Opt in/out of remembering grid; restart | Only agreed preference retained; opt-out removes it | D |
| AND-20 | Offline/no internet, 15-minute use, warm device | Capture works; responsiveness/thermal impact measured | D |
| AND-21 | Install next version over old APK | Signing compatible and app state preserved | O |
| IOS-01 | Swift/director/core tests and app build at 719319f | Previously passed; rerun CI for final commit | H |
| IOS-02 | No frame yet, expired analysis, stop/switch or camera permission denied | No fabricated people, movement or match scores; exports require fresh analysis | D |
| IOS-03 | Wide-only vs telephoto devices | Actual lens matches selected supported plan | O |
| IOS-04 | Real burst with deliberate blur/blink differences | Best-shot choice based on actual image measurements | O |
| IOS-05 | Portrait/landscape and front camera mirroring | Vision observations align with preview | D |
| IOS-06 | Reference popup/viewer + capture + result review | Entire experience on one iPhone | D |
| IOS-07 | Learning consent, feedback, restart and delete profile | Local aggregate learning updates/resets correctly | D |
| IOS-08 | Online consent off/on; empty/error/slow sources | No lookup without consent; source metadata preserved | D |
| IOS-09 | API offline, 401, 429, timeout and billing failure | Offline capture preserved, actionable sanitized error | D |
| REL-01 | Final commit CI on Android branch | APK/lint, JVM, Swift, iOS, fixtures and container green | D |
| REL-02 | Store signing, data disclosures, attribution, device policy | Ready for chosen internal/closed test track | O |
| GROW-01 | Matched stock-camera pilot, consented ratings and return use | Evidence of useful guidance and repeat value | O |

## Device coverage

Use at least an Android API-29-capable device, a mid-range Samsung, a recent Pixel, and a front-camera-only/self-shot session; on iOS include a wide-only model and a multi-lens model. Include dark, high-key, backlit, cluttered, moving-subject and night scenes. High-key scenes can be intentionally bright; average luminance is a heuristic, not an exposure-error oracle.

For every D row, record device/OS, app version/commit, steps, expected/actual behavior, pass/fail, and a redacted defect note. Do not mark rows passed because the APK compiles. Do not upload private photos or identity/location data into this repository for testing.
