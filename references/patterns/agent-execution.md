# Agent Execution Context

How autonomous agents (Hermes fleet, Claude Code, or other orchestrators) should consume and execute this skill.

## Claude Code Execution

In Claude Code, you have direct terminal access. Execute blueprint commands directly:

```
1. Read SKILL.md → identify stack and triage phase
2. Read the blueprint → get exact commands
3. Execute each phase's commands in order
4. Run verification commands after each phase
5. Pause at 🚧 HUMAN GATE steps — tell user what to do and wait
6. Run verify_stack.sh at the end
```

## Hermes Agent / Paperclip Execution

In an agent fleet context, the Connect skill becomes a structured task plan. The orchestrator (Paperclip) creates issues from the blueprint phases.

### Task Decomposition Pattern

Each blueprint phase becomes a Paperclip issue:

```
Issue: [CONNECT] Phase 0 — CLI Setup
Assigned: Dispatch (or whichever agent has terminal access)
Steps:
  - Install supabase, vercel, stripe CLIs
  - Authenticate each (may require HUMAN GATE for first-time OAuth)
Verification: All three CLIs respond to --version
Depends on: Nothing

Issue: [CONNECT] Phase 1 — Provision Services
Assigned: Dispatch
Steps:
  - Check stripe projects availability
  - If available: stripe projects init + add
  - If not: individual CLI provisioning
  - Capture all credentials to .env
Verification: Phase 1 verification commands pass
Depends on: Phase 0

Issue: [CONNECT] Phase 2 — Database Schema
Assigned: Dispatch
Steps:
  - Run supabase init
  - Create migration file
  - Push migrations
Verification: All tables return HTTP 200
Depends on: Phase 1

Issue: [CONNECT] Phase 3 — Stripe Wiring
Assigned: Dispatch
Steps:
  - Create products and prices
  - Create webhook endpoint (needs deployment URL from Phase 1)
  - Save webhook secret
Verification: stripe webhook_endpoints list shows endpoint
Depends on: Phase 1, Phase 2

Issue: [CONNECT] Phase 4 — Env Sync + Redeploy
Assigned: Dispatch
Steps:
  - Set all env vars in Vercel
  - Redeploy to production
Verification: vercel env ls shows all vars, deployment returns 200
Depends on: Phase 3

Issue: [CONNECT] Phase 6 — Final Verification
Assigned: Sentinel (monitoring agent)
Steps:
  - Run verify_stack.sh
  - Report results to Telegram
Verification: All checks pass
Depends on: Phase 4
```

### Human Gates in Agent Context

When an agent hits a 🚧 HUMAN GATE, it should:
1. Create a Paperclip issue tagged `BLOCKED:HUMAN`
2. Send notification via Sentinel → Telegram
3. Include: exactly what the human needs to do, what URL to visit, what values to paste back
4. Wait for human to update the issue with the needed values
5. Resume execution

### Credential Handling

Agents should NEVER store credentials in:
- Issue descriptions
- Git commits
- Log files
- Chat messages

Instead:
- Write to `.env.local` (local) or set via `vercel env add` (remote)
- Reference by variable name, not value
- If credentials must be passed between agents, use the Paperclip vault or env file

### Error Recovery

If a phase fails:
1. Log the exact error message
2. Check the blueprint's "Common Failure Modes" table
3. If a known failure mode, apply the fix and retry
4. If unknown, create a Paperclip issue tagged `BLOCKED:ERROR` with the full error output
5. Do NOT proceed to the next phase — dependency order is sacred

### Idempotency

Most commands in the blueprint are idempotent (safe to re-run):
- `supabase db push` — re-applies migrations, skips already-applied ones
- `vercel env add` — overwrites with `--force`
- `stripe products create` — creates duplicates (NOT idempotent — check first)
- `vercel --prod --yes` — safe to redeploy anytime

For non-idempotent operations (Stripe product/price creation), the agent should check if the resource already exists before creating:
```bash
# Check if product exists before creating
EXISTING=$(stripe products list --limit=100 | grep '"name": "Pro Plan"')
if [ -z "$EXISTING" ]; then
  stripe products create --name="Pro Plan" ...
fi
```
