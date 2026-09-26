---
slug: merge-readiness
name: Merge Readiness
plugin: flow-slice
phase: construction
execution: ALWAYS
condition: Verify local, pull-request, and human approval evidence before merging to main.
lead_agent: aidlc-delivery-agent
support_agents: []
mode: inline
produces:
  - merge-readiness
consumes:
  - artifact: slice-review
    required: true
  - artifact: build-test-results
    required: true
requires_stage:
  - slice-review
sensors:
  - required-sections
scopes:
  - aidlc-flow-slice
required_sections:
  - Local Readiness
  - Pull Request Readiness
  - Unverified Items
  - Measurements
inputs: Passing tests, the approved review, Git state, pull-request checks, and human approvals
outputs: merge-readiness.md under the engine-resolved record directory
---

# Merge Readiness

Never push, create a pull request, merge, or deploy implicitly.

## Steps

1. Under `## Local Readiness`, record the clean working tree, intended commits,
   latest main integration, repository-wide check command, and fresh result.
2. Ask separately before push and before pull-request creation.
3. Under `## Pull Request Readiness`, record the pull-request URL, green CI,
   resolved Critical and Important findings, and merge-conflict status.
4. Under `## Unverified Items`, list every missing check. An item tied to an
   acceptance criterion blocks merge; any other item requires explicit human
   acceptance.
5. Ask for explicit main-merge approval. Do not deploy.
6. After merge, record the merge commit SHA under `## Pull Request Readiness`.
7. Under `## Measurements`, record elapsed and active time, stage times, human
   interventions, test failures, review returns, available token/cost data,
   changed files and lines, commit count, defect discovery stage, and remaining
   unverified items.
