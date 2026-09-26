---
slug: flow-slice-review
name: Slice Review
plugin: flow
phase: construction
execution: ALWAYS
condition: Review the tested slice once after Build and Test succeeds.
lead_agent: aidlc-architecture-reviewer-agent
support_agents: []
mode: subagent
produces:
  - flow-slice-review
consumes:
  - artifact: flow-slice-contract
    required: true
  - artifact: code-summary
    required: true
  - artifact: build-test-results
    required: true
requires_stage:
  - build-and-test
sensors:
  - required-sections
scopes:
  - flow-slice
required_sections:
  - Spec Compliance
  - Findings
  - Verdict
inputs: The approved slice contract, implementation summary, source diff, and passing test evidence
outputs: flow-slice-review.md under the engine-resolved record directory
---

# Slice Review

This is the slice's only independent review. Do not repeat the disabled Code
Generation reviewer.

## Steps

1. Review `## Spec Compliance` first and map every acceptance criterion to
   source and test evidence.
2. Review code quality, error handling, security, and maintainability second.
3. Record every item under `## Findings` as Critical, Important, or Optional.
4. A Critical or Important item blocks approval. Return to implementation,
   rerun affected tests and the repository-wide check, then review only the
   changed and affected diff.
5. Write `## Verdict` as PASS only when no blocking item remains. Otherwise
   write BLOCKED and list the required fixes.
