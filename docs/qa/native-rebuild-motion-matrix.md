# Native rebuild intro motion QA

## Locked contract

- Source logo: `357×86`, 8-bit RGBA.
- SHA-256:
  `0132e9075a8a3953cc87ae43154be317fb846630ea5e1f7dfbced8fb0860120b`.
- Split: `0.40`, inside the fully transparent source gap `x=139...145`.
- Left word: starts `0.04s`, rises for `0.76s`.
- Right word: starts `0.34s`, rises for `0.76s`.
- Both words use `cubic-bezier(.22, .78, .36, 1)`, `y: 10→0`,
  `scale: .988→1`, and `opacity: 0→1`.
- Source-alpha shine: starts `1.18s`, lasts `0.82s`, and runs once.
- At `2.00s` and later, the renderer uses one unchanged whole source logo.
- Reduce Motion uses one whole logo with only a `0.25s` opacity fade.

## Boundary verification

| Time | Expected state | Result |
| --- | --- | --- |
| `0.00s` | Both words hidden at `y=10`, scale `.988` | PASS |
| `0.04s` | Left word begins | PASS |
| `0.34s` | Right word begins; left already moving | PASS |
| `0.80s` | Left complete; right still moving | PASS |
| `1.10s` | Both words complete; no shine yet | PASS |
| `1.18s` | One-shot source-alpha shine begins | PASS |
| `2.00s` | Exact whole static source; no shine | PASS |
| `2.50s` | Equal to the `2.00s` frame | PASS |

Both native frame-model suites check these timestamps. The easing midpoint is
also locked at `0.911465` to prevent a visually similar but incorrect curve.

## Size and accessibility matrix

| Platform / viewport | Motion | Text | Evidence | Result |
| --- | --- | --- | --- | --- |
| iOS 320pt | Normal | Default | Runtime-equivalent 272pt logo canvas; split render equals whole-logo pixels | PASS |
| iOS 393pt | Normal | Accessibility Large | iPhone 16 simulator capture plus 345pt pixel comparison | PASS |
| iOS Pro Max | Normal | Default | Built app capture at left-only and both-word phases; 357pt max canvas | PASS |
| iOS supported widths | Reduce Motion | Default / large | Whole-logo-only frame tests; no translation, scale delta, or shine | PASS |
| Android 360×800dp | Normal | Default | Compose instrumentation with complementary split layers | PASS |
| Android 320×600dp | Reduce Motion | 200% | Whole logo visible; split and shine absent | PASS |
| Android 720dp-equivalent large screen | Normal and Reduce Motion | 200% | Final APK Task 6 instrumentation rerun at density 240 / font scale 2.0 | PASS |
| Android 272 / 345 / 357dp logo canvases | Normal | N/A | Left and right clip bounds meet exactly with no gap or overlap | PASS |

The iOS split renderer at the `1.10s` all-visible frame is pixel-equal to the
whole-logo renderer at 272pt, 345pt, and 357pt canvas widths. Visual inspection
of the compact, 393pt, and Pro Max simulator captures confirms that `ㅑ` and
`ㄹ` remain intact. Android instrumentation verifies complementary clip bounds
at the same three effective canvas widths.

## Runtime behavior

- The first rebuild presentation, including onboarding, shows the intro before
  bootstrap work begins.
- Completion is published under `last-intro-date` only after playback finishes
  and an owned, versioned `pending` transaction is synchronized/read back on
  the iOS utility queue or committed/read back on Android `Dispatchers.IO`.
- Only that explicit `pending` transaction can repair its recorded predecessor
  after restart. `published` or `superseded` records never overwrite a later
  legacy `last-intro-date` write from another app flow.
- Stable reads, process-wide writer serialization, and request ordering keep a
  fresh store wrapper from accepting an in-memory candidate before the durable
  operation returns. All production `last-intro-date` writers use this path.
  A queued older-day request revalidates after taking the writer lock and again
  at final publication, so a later reserved day cannot be overwritten.
- A durable-write failure restores the previous record without changing the
  public date, keeps the intro active, and exposes the accessible
  `저장 다시 시도` action without recreating the screen.
- Completion is asynchronous end-to-end. Retry remains disabled while a write
  is in flight. Same-day callers, including gates recreated during the write,
  converge on one transaction, while a new-day caller waits for a stale write
  and then claims exactly one current-day write.
- An already-completed current day returns success with zero additional writes
  and does not reopen the intro. Cancelled Android rollover waiters propagate
  cancellation and cannot claim a new write.
- A second start on the same controller cannot reset playback.
- Cancellation is generation-safe and cannot deliver a late completion.
- Reduce Motion is latched for one presentation, so changing the system setting
  mid-playback cannot mix a `0.25s` frame model with a `2.00s` duration, or the
  reverse.
- Local-day keys reevaluate the current time zone. Active/date/time-zone
  notifications refresh the gate, and UTC→Seoul travel is covered on both
  platforms.
- Refresh cannot consume an in-memory value while persistence is pending.
  Completion rechecks the current local day after durable storage, so a
  midnight or time-zone rollover keeps the new day's intro active.
- A valid iOS deep link is resolved first, awaits durable persistence, applies
  dismissal state, and only then routes. Invalid routes and persistence
  failures cannot dismiss or route. A deep link arriving during automatic
  completion joins the matching-day write; after a local-day rollover it waits
  for the stale result, persists the current day, and then routes.

## Final automated gate

- iOS XcodeBuildMCP `test_sim`: `339 passed, 0 failed, 0 skipped`;
  warnings `0`, errors `0`.
- Android fresh ASCII build:
  - JVM: `157 passed, 0 failed`.
  - API-35 emulator: `51 passed, 0 failed`.
  - `assembleDebug`: PASS.
- Task 6 focused: iOS `27/27`, Android JVM `15/15`, Android
  instrumentation `18/18`.
- Android large-screen / 200% Task 6 rerun: `10 passed, 0 failed`.
- Mascot validator: `77 parts: PASS`.
- Native contract validator: PASS.
- Python native contract tests: `24 passed`.
- `plutil -lint` and `git diff --check`: PASS.
