# Environment Variable Management

## The Problem

A typical SaaS app needs 8-15 environment variables across 3-4 environments (local, preview, production). Managing these across services is where secrets leak, deployments break, and hours vanish.

## The Four Environments

| Environment | Purpose | Env File | Hosting |
|---|---|---|---|
| Local dev | Your machine | `.env.local` | localhost:3000 |
| Preview | PR/branch deploys | Vercel auto-sets | *.vercel.app |
| Staging | Pre-prod testing | `.env.staging` or Vercel env | staging.yourapp.com |
| Production | Live users | Vercel env vars | yourapp.com |

## The Canonical Variable Set (Next.js + Supabase + Stripe + Vercel)

```env
# === PUBLIC (safe to expose in browser) ===
NEXT_PUBLIC_SUPABASE_URL=https://<ref>.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=eyJ...
NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY=pk_test_...
NEXT_PUBLIC_APP_URL=http://localhost:3000  # Changes per environment

# === SECRET (server-side only) ===
SUPABASE_SERVICE_ROLE_KEY=eyJ...
STRIPE_SECRET_KEY=sk_test_...
STRIPE_WEBHOOK_SECRET=whsec_...
```

## Setting Variables in Vercel via CLI

```bash
# Pattern: vercel env add <NAME> <environments> <<< "<value>"
# Environments: production, preview, development (comma-separated or space-separated)

# Public vars — same across all environments (except APP_URL)
vercel env add NEXT_PUBLIC_SUPABASE_URL production preview development <<< "https://<ref>.supabase.co"
vercel env add NEXT_PUBLIC_SUPABASE_ANON_KEY production preview development <<< "<anon-key>"
vercel env add NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY production preview development <<< "pk_test_..."

# APP_URL — different per environment
vercel env add NEXT_PUBLIC_APP_URL production <<< "https://yourapp.com"
vercel env add NEXT_PUBLIC_APP_URL preview <<< "https://your-app.vercel.app"
vercel env add NEXT_PUBLIC_APP_URL development <<< "http://localhost:3000"

# Secret vars — production only (preview gets test keys separately)
vercel env add SUPABASE_SERVICE_ROLE_KEY production <<< "<service-role-key>"
vercel env add STRIPE_SECRET_KEY production <<< "sk_test_..."
vercel env add STRIPE_WEBHOOK_SECRET production <<< "whsec_..."
```

## Pulling Variables for Local Dev

```bash
# Pull all env vars into .env.local for local development
vercel env pull .env.local
```

This creates a `.env.local` file with all the variables set for the `development` environment.

## Variable Verification Script

Run this after setting up all variables to ensure nothing is missing:

```bash
#!/bin/bash
REQUIRED_VARS=(
  "NEXT_PUBLIC_SUPABASE_URL"
  "NEXT_PUBLIC_SUPABASE_ANON_KEY"
  "SUPABASE_SERVICE_ROLE_KEY"
  "NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY"
  "STRIPE_SECRET_KEY"
  "STRIPE_WEBHOOK_SECRET"
  "NEXT_PUBLIC_APP_URL"
)

echo "Checking environment variables..."
MISSING=0
for VAR in "${REQUIRED_VARS[@]}"; do
  if [ -z "${!VAR}" ]; then
    echo "❌ MISSING: $VAR"
    MISSING=$((MISSING + 1))
  else
    # Show first 10 chars + ... for security
    VALUE="${!VAR}"
    echo "✅ SET: $VAR = ${VALUE:0:10}..."
  fi
done

if [ $MISSING -gt 0 ]; then
  echo ""
  echo "⚠️  $MISSING variables missing. App will not function correctly."
  exit 1
else
  echo ""
  echo "✅ All required variables are set."
fi
```

## Test vs. Live Mode (Stripe)

Stripe has parallel test and live environments. Keys are prefixed:
- Test: `pk_test_...` / `sk_test_...`
- Live: `pk_live_...` / `sk_live_...`

Products, prices, customers, and subscriptions are separate between modes. When switching to production:

1. Create new products/prices in live mode
2. Create a new webhook endpoint with live mode enabled
3. Get new webhook signing secret
4. Update all three Stripe env vars in Vercel production environment
5. Redeploy

## Security Rules

1. **Never commit `.env.local`** — add to `.gitignore`
2. **`NEXT_PUBLIC_` prefix** means the variable is bundled into client-side JavaScript. Only use for truly public values.
3. **Service role keys** are equivalent to database admin access. Never expose in browser.
4. **Webhook secrets** prove that incoming requests are from Stripe. If leaked, attackers can forge webhook events.
5. **Rotate immediately** if any secret is committed to git. Supabase, Stripe, and Vercel all support key rotation.
