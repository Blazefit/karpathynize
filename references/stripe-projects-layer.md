# Stripe Projects Integration Layer

Stripe Projects is a CLI plugin that handles bulk provisioning of services. When available, it replaces the individual service provisioning steps (Layer 1 in the dependency graph) with single commands. It does NOT replace the wiring steps (Layer 3) — you still need to configure webhooks, auth redirects, etc. manually.

## Detection

```bash
# Check if the projects plugin is installed
stripe projects --help 2>&1 | grep -q "projects" && echo "available" || echo "not_available"

# If not installed but user wants it:
stripe plugin install projects
```

**Status as of March 2026:** Stripe Projects is in developer preview. Access requires registration at projects.dev. Not all users will have it.

## Available Providers (as of March 2026)

| Provider | Service Category | Command |
|---|---|---|
| Vercel | Hosting | `stripe projects add vercel/project` |
| Railway | Hosting | `stripe projects add railway/project` |
| Supabase | Database | `stripe projects add supabase/database` |
| Neon | Database | `stripe projects add neon/database` |
| PlanetScale | Database | `stripe projects add planetscale/database` |
| Turso | Database | `stripe projects add turso/database` |
| Clerk | Auth | `stripe projects add clerk/auth` |
| PostHog | Analytics | `stripe projects add posthog/analytics` |
| Chroma | AI/Vector DB | `stripe projects add chroma/database` |
| RunloopAI | AI/Compute | `stripe projects add runloopai/compute` |

**Notable absence:** Resend is not yet a Stripe Projects provider. Use Resend CLI directly.

## Usage Pattern

```bash
# 1. Initialize
stripe projects init <project-name>

# 2. Add services
stripe projects add <provider>/<service>
# This creates accounts, provisions resources, and stores credentials in the vault

# 3. Sync credentials to local .env
stripe projects env sync
# This writes all API keys and URLs to your .env file

# 4. Check status
stripe projects status
# Shows all provisioned services, their status, and credential availability
```

## What Stripe Projects Does vs. Doesn't Do

### DOES handle (replaces manual provisioning):
- Creating accounts on each provider
- Provisioning resources (database instances, hosting projects)
- Generating and storing API keys securely
- Syncing credentials to .env files
- Managing billing across providers via Shared Payment Tokens
- Upgrading/downgrading service tiers

### DOES NOT handle (still need manual/blueprint steps):
- Database schema migrations
- RLS policies and security rules
- Webhook endpoint creation and configuration
- Auth redirect URL configuration
- CORS configuration
- Domain DNS setup
- Product/price creation in Stripe
- Cross-service wiring logic
- Application code for webhook handlers

## Layered Strategy

Use Stripe Projects for Layer 1 (provisioning) when available:

```
IF stripe_projects_available:
    Layer 1: stripe projects init + add commands → env sync
    Layer 2-4: Follow blueprint wiring steps (unchanged)
ELSE:
    Layer 1: Individual CLI provisioning (supabase projects create, vercel, etc.)
    Layer 2-4: Follow blueprint wiring steps (unchanged)
```

The wiring steps in Layers 2-4 are identical regardless of how you provisioned. Stripe Projects saves time on account creation and key management, but the hard part (making services talk to each other) remains the same.

## Credential Management

Stripe Projects stores credentials in a vault and syncs them to `.env`. The credential names may differ from what you'd manually set:

| Stripe Projects Env Var | Your App Expects | Action |
|---|---|---|
| `SUPABASE_URL` | `NEXT_PUBLIC_SUPABASE_URL` | Rename or alias in .env |
| `SUPABASE_ANON_KEY` | `NEXT_PUBLIC_SUPABASE_ANON_KEY` | Rename or alias |
| Various | App-specific names | Map after sync |

After `stripe projects env sync`, review the generated `.env` and rename variables to match your app's expectations. Stripe Projects uses its own naming conventions that may not match your framework's conventions.
