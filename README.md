# Karpathynize

**Wire together production SaaS stacks from your terminal. No browser tabs. No dashboard clicking. No copy-pasting secrets across 15 tabs.**

A [Claude Code](https://claude.ai/claude-code) skill that turns the 80% of developer time spent on service configuration into deterministic, agent-executable steps.

---

## The Problem

You can vibe-code a full app in 20 minutes. Then you spend 4 hours making Stripe talk to Supabase.

This is the **Karpathy Problem** — named after [Andrej Karpathy's observation](https://x.com/kaboroo/status/1903517394874077277) that the hardest part of shipping isn't the code, it's the wiring:

- Creating accounts across 5 services
- Getting API keys from 5 different dashboards
- Configuring webhooks that need a deployment URL you don't have yet
- Setting up auth redirects that create chicken-and-egg problems
- Managing environment variables across dev, preview, and production
- Making 15 different services talk to each other in the right order

Every one of these steps traditionally requires opening a browser, clicking through a dashboard, and copy-pasting secrets around. It's tedious, error-prone, and completely invisible in tutorials.

**Karpathynize encodes the CLI/API equivalent of every browser action** so an AI agent can wire your entire stack without you touching a browser.

---

## What's Inside

```
karpathynize/
├── SKILL.md                          # Main skill instructions
├── references/
│   ├── blueprints/                   # 4 complete stack recipes
│   │   ├── next-supabase-stripe-vercel.md
│   │   ├── next-clerk-neon-stripe-vercel.md
│   │   ├── cloudflare-pages-d1-stripe.md
│   │   └── next-firebase-stripe-vercel.md
│   ├── services/                     # 14 service reference files
│   │   ├── supabase.md    ├── cloudflare.md
│   │   ├── vercel.md      ├── firebase.md
│   │   ├── stripe.md      ├── github-oauth.md
│   │   ├── clerk.md       ├── linear.md
│   │   ├── neon.md        ├── n8n.md
│   │   ├── railway.md     ├── make.md
│   │   ├── resend.md      └── posthog.md
│   └── patterns/                     # Cross-cutting guides
│       ├── dependency-graph.md
│       ├── env-var-management.md
│       └── agent-execution.md
└── scripts/                          # Executable tools
    ├── verify_stack.sh               # Smoke test all connections
    ├── provision_env.sh              # Collect + push env vars
    └── check_staleness.sh            # Detect CLI changes
```

---

## Install

### Option A: Clone and copy (recommended)

```bash
git clone https://github.com/Blazefit/karpathynize.git ~/.claude/skills/karpathynize
```

### Option B: Download .skill file

Grab `karpathynize.skill` from the [latest release](https://github.com/Blazefit/karpathynize/releases) and install it in Claude Code.

---

## Quick Start

Once installed, just tell Claude what you need. The skill triggers automatically.

**Start from zero:**
> "Set up my stack — I need auth, a database, payments, and hosting for a Next.js SaaS app"

**Wire a specific service:**
> "Connect Stripe webhooks to my Vercel deployment"

**Use a specific stack:**
> "Karpathynize this with Cloudflare Pages, D1, and Stripe"

**Fix wiring issues:**
> "My Stripe webhooks are returning 401, help me debug"

**Just verify everything works:**
> "Run verify_stack.sh and tell me what's broken"

---

## Supported Services (14)

| Service | What it does | CLI |
|---|---|---|
| **Supabase** | Auth + PostgreSQL + Realtime | `supabase` |
| **Vercel** | Hosting + Serverless + Edge | `vercel` |
| **Stripe** | Payments + Subscriptions + Billing | `stripe` |
| **Clerk** | Auth + User Management | Dashboard API |
| **Neon** | Serverless PostgreSQL + Branching | `neonctl` |
| **Cloudflare** | Workers + Pages + D1 + R2 + KV | `wrangler` |
| **Firebase** | Auth + Firestore + Functions + Hosting | `firebase` |
| **Railway** | Full-stack hosting + Docker | `railway` |
| **GitHub** | OAuth + API + Webhooks | `gh` |
| **Linear** | Issue tracking + Webhooks (GraphQL) | API |
| **Resend** | Transactional email | API |
| **PostHog** | Analytics + Feature flags | API |
| **n8n** | Workflow automation (self-hosted) | `n8n` |
| **Make** | Workflow automation (cloud) | API |

Each service has a complete reference file with exact CLI commands, common patterns, human gates (things that genuinely require a browser), and a failure modes table.

---

## Blueprints (4 Architecture Paths)

Blueprints are step-by-step recipes for complete stacks. Each one follows a strict dependency order — you can't wire webhooks before you have a deployment URL.

### The Golden Path: Next.js + Supabase + Stripe + Vercel
The canonical indie SaaS stack. PostgreSQL, built-in auth, payments, serverless hosting. Start here if you're not sure.

### Alternative Auth: Next.js + Clerk + Neon + Stripe + Vercel
Swap Supabase auth for Clerk's pre-built UI. Neon for the database with instant branching.

### Edge-Native: Cloudflare Pages + D1 + Workers + Stripe
Everything at the edge. SQLite database, V8 isolates, zero cold starts, single vendor. Fundamentally different architecture from the Vercel path.

### Google Ecosystem: Next.js + Firebase + Stripe + Vercel
Firestore (NoSQL), Firebase Auth with drop-in UI, Cloud Functions handle webhooks independently from your web app.

---

## Scripts

### `verify_stack.sh` — Is everything connected?

```bash
./scripts/verify_stack.sh
```

Checks env vars, API reachability, database tables, Stripe products/webhooks. Outputs a color-coded report with pass/fail/warning for each check.

### `provision_env.sh` — Collect and push secrets

```bash
./scripts/provision_env.sh              # Interactive — walks you through each value
./scripts/provision_env.sh --validate   # Check .env.local values are correctly formatted
./scripts/provision_env.sh --push vercel      # Push to Vercel
./scripts/provision_env.sh --push cloudflare  # Push to Cloudflare Pages
```

Auto-detects your stack from `package.json`. Knows that Stripe keys start with `sk_test_`, Firebase keys with `AIza`, etc. Validates before pushing.

### `check_staleness.sh` — Are the docs still accurate?

```bash
./scripts/check_staleness.sh --snapshot   # Create baseline
./scripts/check_staleness.sh              # Compare current CLIs to baseline
./scripts/check_staleness.sh --report     # Detailed diff of changes
```

Captures `--help` output from 7 CLIs and their subcommands. When a service changes its flags, this tells you which reference files need updating.

---

## How It Works

The skill uses a three-layer system:

1. **Triage** — Figures out what you already have and what you need. Skips phases you've already completed.

2. **Blueprints + Service Refs** — Provides exact CLI commands in dependency order. Every command is copy-pasteable and agent-executable.

3. **Verification** — After each phase, verifies the connection works before moving to the next. No "deploy and pray."

Operations that genuinely require a browser (first-time Stripe identity verification, OAuth app creation in GitHub/Google) are flagged as **Human Gates** with exact instructions on what URL to visit and what to copy back.

---

## Who This Is For

- **Vibe coders** who can build features but drown in DevOps
- **Indie hackers** shipping SaaS apps solo
- **AI agents** (Hermes, Claude Code, custom orchestrators) that need to provision infrastructure programmatically
- **Anyone** who's lost an afternoon to "why is my webhook returning 401"

---

## Contributing

### Add a service reference

1. Create `references/services/your-service.md`
2. Follow the pattern: CLI auth, core operations, common patterns, human gates, failure modes table
3. Add the service to the dependency graph in `references/patterns/dependency-graph.md`
4. Update the service list in `SKILL.md`

### Add a blueprint

1. Create `references/blueprints/your-stack.md`
2. Follow the phase structure: Prerequisites → Provisioning → Schema → Wiring → Env Sync → Verification
3. Each phase must have a verification step
4. Add to the blueprint list in `SKILL.md`

### Report stale commands

If a CLI flag changed and a reference file is outdated, open an issue. Even better: run `check_staleness.sh --report` and paste the diff.

---

## License

MIT
