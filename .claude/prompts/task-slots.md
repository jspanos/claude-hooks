# Task Slots

The fields that decide whether a prompt gets a good first-shot result, by task type.

Used by `hooks/context/prompt-triage.sh` (injects one section when an expensive task
arrives underspecified) and by the `spec` skill (walks them interactively).

Format contract — the hook extracts by exact `## <type>` header, so keep headers
matching the classifier types in `prompt-triage.sh`: `feature`, `debug`, `refactor`,
`research`, `ops`, plus the ungated `review`, `tests`, `explain`. One slot per line,
`- **Name** — what it answers`. Keep each section at 8 lines or fewer: this text is
injected into a live context window. Everything above the first `## ` is never
injected, so this preamble is free at runtime — it's reference for a human.

---

## How to write the prompt (applies to every type)

**Order matters: context first, request last.** Putting reference material at the top
and the actual ask at the bottom measurably outperforms the reverse on long prompts.
For multi-part prompts, delineate sections with XML tags.

**Lead with why, not just what.** The highest-leverage single habit:

> I'm working on [larger task] for [who it's for]. They need [what the output enables].
> With that in mind: [request].

This lets the model connect your task to information you didn't think to mention.

**State the outcome and the constraints — not the method.** Current models degrade when
handed step-by-step choreography for judgment work. Say what "done" looks like and what
must not change; leave the how to the model. Numbered steps only where order genuinely
matters (destructive operations, auth flows, migrations).

**Give it a way to check itself.** A prompt with no verification path leaves "looks
done" as the only available signal. Name the test, the command, or the observable.

**Minimal is not the same as short.** Start with the smallest prompt that carries real
context, then add detail in response to failures you actually observe — not
preemptively. Context is never the cruft; specific stale instructions are.

**Say it once, plainly.** `CRITICAL:` / `You MUST` / `NEVER` have diminishing returns
and can anchor toward the failure you're naming. One plain constraint with its reason
beats three in capitals. Skip "be thorough" and "think step by step" — both are
already default behavior, and the latter is now a configuration setting, not prose.

### The five failure modes these slots exist to prevent

1. **No verification** — nothing to distinguish finished from plausible-looking.
2. **No scope boundary** — vague exploration reads hundreds of files and pollutes context.
3. **Unstated constraints** — edge cases, perf targets, and compat rules left implicit.
4. **Symptom without root cause** — an error reported with no text and no repro invites guessing.
5. **No "done" signal** — the model stops early or over-verifies because the bar was never set.

## feature
- **Outcome** — what someone can do after this that they can't now
- **Interface** — the signature, route, schema, or CLI shape callers will see
- **Target** — which files change; where new code belongs
- **Pattern** — an existing file to imitate, so the result matches the codebase
- **Acceptance** — the check that proves it works (test, command, example in→out)
- **Scope fence** — what stays untouched
- **Constraints** — auth, perf, back-compat, or platform limits that apply

## debug
- **Symptom** — exact error text, or actual vs expected output
- **Repro** — the command or steps; deterministic or intermittent
- **Last known good** — when it worked, and what changed since
- **Environment** — local / CI / staging / prod, plus relevant versions
- **Already ruled out** — what you tried, so it isn't retried
- **Fix bar** — stop the bleeding now, or find and fix the root cause
- **Urgency** — who is blocked and how hard

## refactor
- **Motivation** — the concrete pain ("three callers duplicate this parsing"), not "it's messy"
- **Invariant** — behavior that must not change, and the test that proves it
- **Boundary** — files in scope; files frozen
- **Target shape** — the end state, or explicitly "you propose it"
- **Migration** — one commit or incremental; any back-compat window
- **Verification** — the test or benchmark establishing equivalence before/after

## research
- **Decision** — what you will do differently depending on the answer
- **Criteria** — what would settle it, ranked; the disqualifiers
- **Constraints** — stack, budget, team skills, licensing, timeline
- **Candidates** — options already on the table, and any already rejected
- **Depth** — a 10-minute read, or a real evaluation with a spike
- **Deliverable** — recommendation, comparison table, or written brief

## ops
- **Environment** — target, and whether production is in play
- **Current state** — what is deployed or configured right now
- **Desired state** — the end configuration
- **Verification** — how to confirm healthy afterward
- **Rollback** — the exact revert path, and whether it has ever been exercised
- **Blast radius** — what breaks if this is wrong, and who notices first
- **Approval** — whose sign-off or change window is required

## review
- **Target** — diff, branch, PR number, or paths
- **Bar** — correctness only, or also style, perf, security
- **Suspicions** — areas you already think are weak
- **Output** — inline PR comments, a findings list, or apply the fixes

## tests
- **Behavior** — the unit under test and the assertions that matter
- **Conventions** — framework, and an existing test file to imitate
- **Coverage goal** — happy path only, or edge and error cases too
- **Isolation** — available fixtures/mocks; what must not touch network or disk
- **Enough** — what makes the suite done rather than endless

## explain
- **Audience** — you learning it, or docs for someone else
- **Entry point** — the file, function, or flow to start from
- **Real question** — what you will do with the understanding
- **Output** — prose, diagram, or annotated walkthrough
