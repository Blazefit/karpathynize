---
name: karpathynize
description: "Wire together production SaaS stacks without touching a browser — solving the Karpathy Problem. Use this skill whenever the user wants to provision, connect, configure, or deploy services like Supabase, Vercel, Stripe, Clerk, Resend, PostHog, Neon, Railway, Cloudflare (Workers/Pages/R2/D1), Firebase, Linear, or any combination of cloud services for a web application. Also covers GitHub OAuth setup and wiring. Trigger on phrases like 'set up my stack', 'connect Stripe to Supabase', 'deploy to Vercel', 'deploy to Cloudflare', 'wire up auth', 'configure webhooks', 'provision services', 'set up payments', 'connect my database', 'set up Firebase', 'connect Linear', 'GitHub OAuth', 'get this deployed', 'make this production-ready', 'karpathynize this', or any request involving multiple services that need to talk to each other. Also trigger when the user mentions DevOps pain, IKEA furniture metaphors about services, service glue, the 80% that isn't code, or references vibe-coding apps but struggling with infrastructure. This skill turns the 80% of developer time spent on service configuration into deterministic, agent-executable steps — no browser tabs, no dashboard clicking, no copy-pasting secrets across 15 tabs."
---

# Karpathynize: Zero-Browser Service Wiring

## What This Skill Solves

The hardest part of shipping an app isn't the code — it's the **wiring**: creating accounts across services, getting API keys, configuring webhooks, setting up auth redirects, managing environment variables across dev/prod, and making 15 different services talk to each other. All of this traditionally requires browser tabs, clicking through dashboards, and copy-pasting secrets around.

This skill encodes the CLI/API equivalent of every browser action needed to go from zero to deployed across the most common SaaS stacks. Every step is agent-executable — no human browser interaction required except where a service genuinely has no CLI/API escape hatch (these are explicitly flagged as `🚧 HUMAN GATE` steps).

## Architecture: Three Layers

### Layer 1: Provisioning (Getting accounts + keys)
Check if Stripe Projects CLI is available first — it handles bulk provisioning.
Read `references/stripe-projects-layer.md` for detection and usage.
If unavailable, fall back to individual service CLIs.

### Layer 2: Wiring (Making services talk to each other)
This is the hard part and where most of the skill's value lives.
Connections have **dependency order** — you can't configure Stripe webhooks without a deployment URL.
Read `references/patterns/dependency-graph.md` for the universal ordering rules.

### Layer 3: Verification (Proving it all works)
Every stack setup ends with a verification phase.
Run `scripts/verify_stack.sh` or follow the manual verification checklist in the blueprint.

## How to Use This Skill

### Step 1: Identify the stack

Ask or infer which services the user needs. Common patterns:

| User says | They need |
|---|---|
| "SaaS app with payments" | Next.js + Supabase + Stripe + Vercel |
| "app with auth and database" | Next.js + Supabase (or Clerk + Neon) + Vercel |
| "deploy my Next.js app" | Vercel (possibly + domain config) |
| "set up email sending" | Resend + domain DNS verification |
| "add analytics" | PostHog |
| "the full stack" | Next.js + Supabase + Stripe + Vercel + Resend + PostHog |
| "use Clerk instead of Supabase auth" | Clerk + Neon (or Supabase DB-only) + Vercel |
| "deploy to Railway" | Railway (alt to Vercel — better for backends + Docker) |
| "deploy to Cloudflare" | Cloudflare Pages + Workers + D1/R2 |
| "use Firebase" | Firebase Auth + Firestore + Hosting (+ Cloud Functions) |
| "sign in with GitHub" | GitHub OAuth + your auth provider (Supabase/Clerk/NextAuth) |
| "set up issue tracking" | Linear API + webhooks for DevOps integration |
| "connect X to Y" | Partial wiring — skip to Step 2 |

### Step 2: Triage — What already exists?

Before loading a blueprint, determine what the user already has. This decides which phases to skip.

**Ask or detect:**
- Do you have a Next.js (or other) app codebase? → If no, need scaffolding first
- Do you have any of these services already set up? (Supabase project, Stripe account, Vercel deployment)
- Is anything working locally? In production?

**Phase entry points based on existing state:**

| User's current state | Start at |
|---|---|
| Nothing — truly from zero | Blueprint Phase -1 (scaffolding) then Phase 0 |
| Has code but no services | Blueprint Phase 0 (CLI setup) |
| Has code + services provisioned, not wired | Blueprint Phase 2 (schema) or Phase 3 (wiring) |
| Has local dev working, needs deployment | Blueprint Phase 1B.3 (Vercel deploy) then Phase 3-4 |
| Has deployment, needs to wire one specific service | Jump to that service's section in Phase 3 |
| Has everything, just needs verification | Blueprint Phase 6 or run `verify_stack.sh` |

This triage prevents re-doing work and gets the user to the right phase immediately.

### Step 3: Load the blueprint (or compose)

**If the stack matches a blueprint** (read from `references/blueprints/`):
- **`next-supabase-stripe-vercel.md`** — The golden path SaaS stack (Supabase auth + PostgreSQL). Start here for most apps.
- **`next-clerk-neon-stripe-vercel.md`** — Alternative with Clerk auth + Neon DB. Choose when you want pre-built auth UI and instant DB branching.
- **`cloudflare-pages-d1-stripe.md`** — Edge-native stack. Everything on Cloudflare (Pages + D1 + Workers) + Stripe. Zero cold starts, single vendor, SQLite at the edge. Choose for globally distributed apps or minimal vendor count.
- **`next-firebase-stripe-vercel.md`** — Google ecosystem stack. Firebase Auth + Firestore (NoSQL) + Cloud Functions + Stripe + Vercel. Choose for document-oriented data, built-in auth UI, or when already in the GCP ecosystem. Key difference: webhooks run on Cloud Functions, not your Next.js app.

**If the stack doesn't match any blueprint**, compose a custom plan:
1. Read `references/patterns/dependency-graph.md` for the universal ordering rules
2. Read the relevant service references from `references/services/`
3. Follow the 5-layer dependency order: CLIs → Core Services → Deploy → Wire → Verify
4. For each service, the service reference file contains exact CLI commands
5. For cross-service connections, apply the wiring patterns from `references/patterns/`

**Adding services to an existing blueprint** (e.g., adding Resend to the golden path):
1. Run the golden path blueprint for the core services
2. After Phase 4, read the additional service's reference file
3. Provision it (Layer 1), wire it (Layer 3 — usually just env vars + API key), verify it

### Step 4: Check provisioning layer

Read `references/stripe-projects-layer.md` to determine if Stripe Projects is available.
- If yes: use it for bulk provisioning, then continue to wiring steps in the blueprint.
- If no: the blueprint includes per-service CLI fallback commands.

### Step 5: Execute in dependency order

Follow the blueprint's numbered phases, starting from the entry point determined in Step 2.

**Critical rule:** After each phase, verify before moving to the next. Don't batch everything and hope it works.

### Step 6: Run verification

Execute the verification checklist at the end of the blueprint. Every connection should be tested — not assumed.

## Service Reference Files

For individual service deep-dives, read from `references/services/`:

**Core stack:**
- `supabase.md` — Project creation, migrations, RLS, edge functions, API keys
- `vercel.md` — Deployment, env vars, domains, preview deploys
- `stripe.md` — Products, prices, webhooks, customer portal, test→prod
- `clerk.md` — Auth, user management, organizations, OAuth, middleware
- `neon.md` — Serverless Postgres, branching, neonctl CLI, connection pooling

**Alternative hosting & platforms:**
- `cloudflare.md` — Workers, Pages, D1 (edge SQLite), R2 (object storage), KV, DNS
- `firebase.md` — Auth, Firestore, Cloud Functions, Hosting, emulators
- `railway.md` — Full-stack hosting, built-in databases, Docker support

**Integrations & add-ons:**
- `github-oauth.md` — OAuth app setup, API via gh CLI, repo webhooks, wiring to auth providers
- `linear.md` — Issue tracking API (GraphQL), webhooks, SDK, DevOps automation
- `resend.md` — Domain verification, API setup, email templates
- `posthog.md` — Analytics, feature flags, session recording

**Workflow automation:**
- `n8n.md` — Open-source workflow automation (self-hosted or cloud), webhooks, API, Docker deployment
- `make.md` — Visual workflow automation (cloud), 1500+ integrations, webhook patterns

Each file contains the complete CLI/API command reference for that service, including both the "happy path" and common failure modes.

## Wiring Pattern References

For cross-cutting concerns, read from `references/patterns/`:
- `dependency-graph.md` — Universal ordering rules for service connections
- `env-var-management.md` — How to manage secrets across dev/local/preview/prod
- `agent-execution.md` — How autonomous agents (Hermes fleet, Claude Code) should consume blueprints as structured task plans

## Human Gates

Some operations genuinely require browser interaction because the service has no CLI/API equivalent. These are flagged as `🚧 HUMAN GATE` in blueprints. Common ones:
- First-time Stripe account creation (requires identity verification)
- Domain purchase (registrars rarely have agent-friendly APIs)
- OAuth app creation on Google/GitHub (requires browser consent flow)
- First-time billing setup on some services

When you hit a human gate, tell the user exactly what to do, what URL to visit, and what values to copy back. Minimize their browser time to the absolute minimum.

## Execution Context

This skill works in two contexts:
1. **Claude Code** — Direct terminal access. Execute commands directly.
2. **Agent frameworks (Hermes, etc.)** — Provide the commands as structured task lists. The orchestrator dispatches them.

In either context, the knowledge is the same — the blueprints and service references contain the exact commands. The difference is just whether you execute them yourself or emit them as instructions.

## Scripts

The `scripts/` directory contains executable tools that complement the knowledge in blueprints:

- **`verify_stack.sh`** — Verify all services are connected and working. Checks env vars, API reachability, database tables, and webhook configuration.
- **`provision_env.sh`** — Collect, validate, and push environment variables. Auto-detects your stack from `package.json`, knows the expected format for each service's env vars (e.g., Stripe keys start with `sk_test_`), and can push to Vercel or Cloudflare Pages.
  - `./scripts/provision_env.sh` — Interactive collection
  - `./scripts/provision_env.sh --validate` �� Validate .env.local
  - `./scripts/provision_env.sh --push vercel` — Push to Vercel
  - `./scripts/provision_env.sh --push cloudflare` — Push to Cloudflare Pages
- **`check_staleness.sh`** — CLI change detection (see Staleness Detection below).

## Staleness Detection

The skill includes a CLI snapshot system that detects when service CLIs change their flags or commands — which means the service reference files might be outdated.

```bash
# First time: create a baseline snapshot of all tracked CLI --help outputs
./scripts/check_staleness.sh --snapshot

# Later: compare current CLIs against the snapshot
./scripts/check_staleness.sh

# Detailed diff when changes are detected
./scripts/check_staleness.sh --report
```

The script tracks 7 CLIs (supabase, vercel, stripe, wrangler, firebase, gh, neonctl) and their key subcommands. When it detects changes, it tells you which service reference files need review.

Run this periodically (monthly is fine) or after upgrading any CLI. Can be wired to a cron job or the `schedule` skill for automatic monitoring.

## Key Principles

1. **Dependency order is sacred.** Never skip ahead. The blueprint phases exist for a reason.
2. **Verify before proceeding.** Each phase has a verification step. Use it.
3. **Secrets never go in code.** Everything through env vars. `.env.local` for dev, Vercel/service dashboards for prod.
4. **Stripe Projects when available, direct CLIs when not.** Always check first.
5. **Flag human gates honestly.** Don't pretend you can do something you can't.
6. **Test mode first, always.** Use Stripe test keys, Supabase dev branches, Vercel preview deployments. Switch to prod only after the full flow works end-to-end.
