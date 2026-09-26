---
slug: slice-contract
name: Slice Contract
plugin: flow-slice
phase: inception
execution: ALWAYS
condition: Define one small user-visible slice before implementation.
lead_agent: aidlc-product-agent
support_agents: []
mode: inline
produces:
  - requirements
  - slice-contract
consumes: []
requires_stage:
  - state-init
sensors:
  - required-sections
scopes:
  - aidlc-flow-slice
summary_confirmation: if-present
required_sections:
  - Acceptance Criteria
  - Boundary Test
  - Merge Safety
inputs: The requested user-visible change and current workspace state
outputs: requirements.md and slice-contract.md under the engine-resolved record directory
---

# Slice Contract

Follow the active stage protocol and keep this contract short.

## Steps

1. State one to three externally observable acceptance criteria under
   `## Acceptance Criteria`.
2. Name the first boundary test that must fail before implementation under
   `## Boundary Test`.
3. List changed external boundaries and required round-trip evidence.
4. Under `## Merge Safety`, decide whether this slice can merge safely in one
   pull request without a feature flag.
5. If it cannot, stop and ask the human to choose slice splitting, a feature
   flag, or bundled delivery. Do not ask when the slice is already safe.
6. Write the same approved contract to `requirements.md` and
   `slice-contract.md` at the engine-resolved record directory.
7. Open one approval gate for the complete contract.
