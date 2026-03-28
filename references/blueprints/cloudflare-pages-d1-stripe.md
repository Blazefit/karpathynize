# Blueprint: Cloudflare Pages + D1 + Workers + Stripe

The edge-native stack. Everything runs at the edge — your app, your database, your serverless functions. No centralized servers. This is architecturally different from the Vercel/Supabase golden path: instead of a Node.js runtime hitting a PostgreSQL database, you have V8 isolates hitting SQLite at the edge.

**Services:** Cloudflare Pages (hosting + SSR), D1 (edge SQLite), Workers (serverless), Stripe (payments)
**Total time:** ~25 minutes agent-executed, ~5 minutes human gates
**Prerequisites:** Node.js 18+, npm, Git, Wrangler CLI

**When to use this instead of the golden path:**
- You want global edge performance (every request served from nearest PoP)
- Your data model fits SQLite (most CRUD apps do)
- You want a single vendor for hosting + database + serverless + DNS + CDN
- You want to avoid cold starts entirely (Workers have ~0ms cold start)
- You're building a content site, API, or lightweight SaaS

**When NOT to use this:**
- You need PostgreSQL features (complex joins, extensions, full-text search beyond FTS5)
- You need real-time subscriptions (use Supabase for that)
- You need built-in auth (Cloudflare has no auth service — bring Clerk, Lucia, or roll your own)
- Your app needs more than 10GB database (D1 limit per database)

---

## Phase 0: Prerequisites & CLI Setup

### 0.1 Install Wrangler

```bash
# Install Wrangler (Cloudflare's CLI for everything)
npm install -g wrangler

# Install Stripe CLI
brew install stripe/stripe-cli/stripe

# Verify
wrangler --version
stripe --version
```

### 0.2 Authenticate CLIs

```bash
# Wrangler — opens browser for OAuth
wrangler login

# Verify auth
wrangler whoami
# Should show your account name and ID

# Stripe — opens browser for device auth
stripe login
```

**🚧 HUMAN GATE:** First-time Cloudflare account creation at dash.cloudflare.com. First-time Stripe account creation requires identity verification.

---

## Phase -1: Project Scaffolding (skip if you have code)

```bash
# Create Next.js app (Cloudflare-compatible)
npx create-next-app@latest my-edge-app \
  --typescript --tailwind --eslint --app --src-dir --import-alias "@/*"

cd my-edge-app

# Install Cloudflare adapter for Next.js
npm install @cloudflare/next-on-pages

# Install D1 ORM (Drizzle recommended for D1)
npm install drizzle-orm
npm install -D drizzle-kit

# Install Stripe
npm install stripe @stripe/stripe-js

# Initialize git
git init && git add -A && git commit -m "Initial scaffold"
```

### Configure next.config for Cloudflare

```javascript
// next.config.js — edge runtime required for Cloudflare
/** @type {import('next').NextConfig} */
const nextConfig = {
  // All routes run on edge runtime by default on Cloudflare Pages
};
module.exports = nextConfig;
```

### Add wrangler.toml

```bash
cat > wrangler.toml << 'EOF'
name = "my-edge-app"
compatibility_date = "2024-01-01"
pages_build_output_dir = ".vercel/output/static"

[[d1_databases]]
binding = "DB"
database_name = "my-edge-app-db"
database_id = ""  # Will be filled after Phase 1
EOF
```

---

## Phase 1: Service Provisioning

Unlike the golden path where services are provisioned independently, here everything is under one Cloudflare account. The only external service is Stripe.

### 1.1 Create D1 Database

```bash
# Create the database
wrangler d1 create my-edge-app-db
# Output: database_id = "<id>"

# Save the database ID — update wrangler.toml
# Replace the empty database_id with the actual ID
```

Update `wrangler.toml` with the database ID from the output.

### 1.2 Create Pages Project

```bash
# Create the Pages project
wrangler pages project create my-edge-app

# This just registers the project name — no deployment yet
```

### 1.3 Get Stripe Keys

```bash
stripe config --list
```

**🚧 HUMAN GATE:** Copy API keys from dashboard.stripe.com/apikeys:
- Publishable key (pk_test_...)
- Secret key (sk_test_...)

### Verification: Phase 1

```bash
echo "=== Phase 1 Verification ==="

# D1 database exists
wrangler d1 list | grep "my-edge-app-db" && echo "D1: ✅" || echo "D1: ❌"

# Pages project exists
wrangler pages project list | grep "my-edge-app" && echo "Pages: ✅" || echo "Pages: ❌"

# Stripe connected
stripe config --list | grep "test" && echo "Stripe: ✅" || echo "Stripe: ❌"
```

---

## Phase 2: Database Schema

D1 uses SQLite. Migrations work differently from PostgreSQL — no RLS, no triggers on auth events. Security is enforced at the application layer (your Workers/API routes).

### 2.1 Create Schema with Drizzle

```bash
mkdir -p src/db

cat > src/db/schema.ts << 'EOF'
import { sqliteTable, text, integer, real } from 'drizzle-orm/sqlite-core';

export const users = sqliteTable('users', {
  id: text('id').primaryKey(), // Use your auth provider's user ID
  email: text('email').notNull().unique(),
  name: text('name'),
  stripeCustomerId: text('stripe_customer_id').unique(),
  createdAt: integer('created_at', { mode: 'timestamp' }).$defaultFn(() => new Date()),
});

export const subscriptions = sqliteTable('subscriptions', {
  id: text('id').primaryKey(), // Stripe subscription ID
  userId: text('user_id').references(() => users.id),
  status: text('status').notNull(),
  priceId: text('price_id'),
  currentPeriodEnd: integer('current_period_end', { mode: 'timestamp' }),
  cancelAtPeriodEnd: integer('cancel_at_period_end', { mode: 'boolean' }).default(false),
});

export const products = sqliteTable('products', {
  id: text('id').primaryKey(), // Stripe product ID
  name: text('name'),
  description: text('description'),
  active: integer('active', { mode: 'boolean' }).default(true),
});

export const prices = sqliteTable('prices', {
  id: text('id').primaryKey(), // Stripe price ID
  productId: text('product_id').references(() => products.id),
  unitAmount: integer('unit_amount'),
  currency: text('currency'),
  interval: text('interval'), // 'month' | 'year'
  active: integer('active', { mode: 'boolean' }).default(true),
});
EOF
```

### 2.2 Configure Drizzle

```bash
cat > drizzle.config.ts << 'EOF'
import { defineConfig } from 'drizzle-kit';

export default defineConfig({
  schema: './src/db/schema.ts',
  out: './migrations',
  dialect: 'sqlite',
});
EOF
```

### 2.3 Generate and Apply Migrations

```bash
# Generate SQL migrations from schema
npx drizzle-kit generate

# Apply to local D1 (development)
wrangler d1 migrations apply my-edge-app-db

# Apply to remote D1 (production)
wrangler d1 migrations apply my-edge-app-db --remote
```

### Verification: Phase 2

```bash
# Check tables exist locally
wrangler d1 execute my-edge-app-db --command="SELECT name FROM sqlite_master WHERE type='table'"

# Check tables exist remotely
wrangler d1 execute my-edge-app-db --remote --command="SELECT name FROM sqlite_master WHERE type='table'"

echo "Phase 2: Schema applied ✅"
```

---

## Phase 3: Initial Deployment (Get a URL)

Deploy early to get a URL for Stripe webhooks.

### 3.1 Build and Deploy

```bash
# Build for Cloudflare
npx @cloudflare/next-on-pages

# Deploy to Pages
wrangler pages deploy .vercel/output/static --project-name=my-edge-app

# Output: https://my-edge-app.pages.dev (or similar)
# SAVE THIS URL
```

### Verification: Phase 3

```bash
DEPLOY_URL="https://my-edge-app.pages.dev"  # replace with actual
curl -s -o /dev/null -w "Deployment: HTTP %{http_code}\n" "$DEPLOY_URL"
```

---

## Phase 4: Stripe Wiring

Now that we have a URL, wire Stripe webhooks.

### 4.1 Create Products & Prices

```bash
# Create product
stripe products create \
  --name="Pro Plan" \
  --description="Full access to all features"
# Save prod_... ID

# Create monthly price
stripe prices create \
  --product=<product-id> \
  --unit-amount=2900 \
  --currency=usd \
  -d "recurring[interval]=month"
# Save price_... ID
```

### 4.2 Create Webhook Endpoint

```bash
stripe webhook_endpoints create \
  --url="https://my-edge-app.pages.dev/api/webhooks/stripe" \
  --enabled-events="checkout.session.completed" \
  --enabled-events="customer.subscription.created" \
  --enabled-events="customer.subscription.updated" \
  --enabled-events="customer.subscription.deleted"

# Save whsec_... webhook signing secret
```

### 4.3 Set Secrets

```bash
# Set secrets for the Pages project (these are encrypted at rest)
wrangler pages secret put STRIPE_SECRET_KEY --project-name=my-edge-app
# Enter: sk_test_...

wrangler pages secret put STRIPE_WEBHOOK_SECRET --project-name=my-edge-app
# Enter: whsec_...

wrangler pages secret put NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY --project-name=my-edge-app
# Enter: pk_test_...
```

**Note:** Wrangler `secret put` is interactive (prompts for value). For fully non-interactive agent execution, use the Cloudflare API:

```bash
# Non-interactive alternative via API
curl -X PATCH "https://api.cloudflare.com/client/v4/accounts/<account-id>/pages/projects/my-edge-app" \
  -H "Authorization: Bearer <api-token>" \
  -H "Content-Type: application/json" \
  -d '{
    "deployment_configs": {
      "production": {
        "env_vars": {
          "STRIPE_SECRET_KEY": { "value": "sk_test_...", "type": "secret_text" },
          "STRIPE_WEBHOOK_SECRET": { "value": "whsec_...", "type": "secret_text" },
          "NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY": { "value": "pk_test_..." }
        }
      }
    }
  }'
```

### 4.4 Redeploy

```bash
npx @cloudflare/next-on-pages && \
wrangler pages deploy .vercel/output/static --project-name=my-edge-app
```

### Verification: Phase 4

```bash
# Check webhook endpoint
stripe webhook_endpoints list

# Trigger test event
stripe trigger checkout.session.completed

echo "Phase 4: Stripe wired ✅"
```

---

## Phase 5: Domain Configuration (Optional)

### 5.1 Add Custom Domain

If the domain is already on Cloudflare (nameservers pointed to Cloudflare):

```bash
# Add via API (Cloudflare manages DNS directly)
curl -X POST "https://api.cloudflare.com/client/v4/zones/<zone-id>/dns_records" \
  -H "Authorization: Bearer <api-token>" \
  -H "Content-Type: application/json" \
  -d '{
    "type": "CNAME",
    "name": "app",
    "content": "my-edge-app.pages.dev",
    "proxied": true
  }'
```

**🚧 HUMAN GATE:** If the domain is NOT on Cloudflare, the user must first add the domain to Cloudflare and change nameservers at their registrar.

### 5.2 Update Stripe Webhook URL

```bash
stripe webhook_endpoints update <webhook-endpoint-id> \
  --url="https://app.yourdomain.com/api/webhooks/stripe"
```

---

## Phase 6: Final Verification

```bash
echo "==========================================="
echo "  EDGE STACK VERIFICATION"
echo "==========================================="

DEPLOY_URL="https://my-edge-app.pages.dev"  # or custom domain

# 1. Pages deployment
echo ""
echo "--- Cloudflare Pages ---"
STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$DEPLOY_URL")
echo "Deployment: HTTP $STATUS $([ '$STATUS' = '200' ] && echo '✅' || echo '❌')"

# 2. D1 database
echo ""
echo "--- D1 Database ---"
wrangler d1 execute my-edge-app-db --remote \
  --command="SELECT COUNT(*) as table_count FROM sqlite_master WHERE type='table'" 2>/dev/null \
  && echo "D1 remote: ✅" || echo "D1 remote: ❌"

# 3. Stripe
echo ""
echo "--- Stripe ---"
PRODUCTS=$(stripe products list --limit=1 2>/dev/null | grep -c "id")
echo "Products: $([ $PRODUCTS -gt 0 ] && echo '✅' || echo '❌')"

WEBHOOKS=$(stripe webhook_endpoints list 2>/dev/null | grep -c "$DEPLOY_URL")
echo "Webhook → $DEPLOY_URL: $([ $WEBHOOKS -gt 0 ] && echo '✅' || echo '❌')"

echo ""
echo "==========================================="
```

---

## Key Differences from the Golden Path

| Aspect | Golden Path (Vercel+Supabase) | Edge Stack (Cloudflare) |
|---|---|---|
| Database | PostgreSQL (centralized) | SQLite at edge (distributed) |
| Auth | Supabase Auth (built-in) | Bring your own (Clerk, Lucia, etc.) |
| Hosting | Vercel (Node.js runtime) | Cloudflare Pages (V8 isolates) |
| Cold starts | ~250ms | ~0ms |
| Secrets | `vercel env add` | `wrangler pages secret put` or API |
| Migrations | `supabase db push` | `wrangler d1 migrations apply` |
| Vendor count | 3 (Supabase, Vercel, Stripe) | 2 (Cloudflare, Stripe) |
| Real-time | Built-in (Supabase Realtime) | Not included (add Pusher/Ably/PartyKit) |

## Adding Auth to This Stack

This blueprint deliberately omits auth because Cloudflare doesn't have one. Common additions:

1. **Clerk** — Read `references/services/clerk.md`. Add Clerk middleware, set env vars via `wrangler pages secret put`.
2. **Lucia Auth** — Self-hosted auth using D1 as the session store. No external service needed, but more code.
3. **GitHub OAuth directly** — Read `references/services/github-oauth.md`. Implement the OAuth flow in a Worker/API route.
