---
description: Work out what to do next on pennyWise and propose it
---

1. Read `AGENTS.md` (project rules) and PLAN.md section 8 (milestone status).
2. Run `git status` and `git log --oneline -15`. If there are uncommitted
   changes you did not make, stop and ask the owner whose they are.
3. Check that the last CI runs on `main` are green (api, mobile,
   deploy-config). A red run comes first.
4. List the open items: each milestone row that is not ✅, its **Open**
   part, and the unticked items in PLAN.md section 9 (Play Store checklist).
5. Split them into:
   - **Owner tasks** (needs their accounts, domain, keys or a real phone):
     write the exact steps for the owner.
   - **Agent tasks** (code, tests, docs you can do here).
6. Recommend one agent task: the smallest chunk that moves the release
   forward. Give a short plan (files, tests, commits) and wait for the
   owner's go-ahead before writing code.
