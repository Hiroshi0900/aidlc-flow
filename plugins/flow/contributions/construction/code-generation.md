---
target: code-generation
plugin: flow
adds:
  scopes:
    - flow-slice
  consumes:
    - artifact: flow-requirements
      required: true
    - artifact: flow-slice-contract
      required: true
fragments:
  - anchor: after-step:1
    order: 100
---

## fragment: after-step:1

### Step 1a (flow): Bind implementation to the approved slice contract

For `flow-slice`, read `flow-requirements.md` and `flow-slice-contract.md`
before planning or changing application code. Treat their approved content as
the highest-priority product contract for this stage:

- map every `## Acceptance Criteria` item to an implementation step and test in
  `code-generation-plan.md`;
- run the test named by `## Boundary Test` as the first TDD Red, then implement
  the minimum Green change and refactor only while the boundary remains green;
- carry `## Merge Safety` constraints into the plan, including its case-specific
  feature-flag decision, and do not broaden the slice beyond that decision.

If the two artifacts disagree or any required section is missing, stop and ask
for the Slice Contract to be corrected rather than inventing requirements.
