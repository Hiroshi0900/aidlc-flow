---
name: aidlc-flow-slice
plugin: flow-slice
depth: Minimal
testStrategy: Standard
keywords:
  - vertical slice
  - slice
  - main merge
description: Deliver one testable user-visible slice through review and merge readiness
skeleton: off
runner: true
review_cap: none
change_control: relaxed
sensors: on
learnings: off
summary_confirmation: off
---

# aidlc-flow-slice scope

Use one intent, one branch, and one pull request for a small user-visible slice.
The path is Slice Contract, Code Generation, Build and Test, Slice Review, and
Merge Readiness. Do not create horizontal Units.
