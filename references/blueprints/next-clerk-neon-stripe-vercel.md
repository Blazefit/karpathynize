# Blueprint: Next.js + Clerk + Neon + Stripe + Vercel

Alternative SaaS stack using Clerk for auth and Neon for database. Choose this over the golden path when you want pre-built auth UI components (Clerk) and instant database branching (Neon).

**Services:** Clerk (auth + user management), Neon (serverless Postgres), Stripe (payments), Vercel (hosting)
**Total time:** ~25 minutes agent-executed, ~5 minutes human gates
**Prerequisites:** Node.js 18+, npm/pnpm, Git

---

## Phase -1: Project Scaffolding (skip if you have a codebase)

```bash
npx create-next-app@latest my-saas-app \
  --typescript --tailwind --eslint --app --src-dir --import-alias "@/*"
cd my-saas-app
git init && git add -A && git commit -m "Initial scaffold"

# Install stack dependencies
npm install @clerk/nextjs stripe @stripe/stripe-js @neondatabase/serverless
npm install -D drizzle-kit drizzle-orm  # or prisma
```

---

## Phase 0: CLI Setup

```bash
# Neon CLI
brew install neonctl  # or: npm install -g neonctl

# Vercel CLI
npm install -g vercel

# Stripe CLI
brew install stripe/stripe-cli/stripe

# Authenticate all
neonctl auth
vercel login
stripe login
```

**🚧 HUMAN GATE:** Create Clerk account + application at clerk.com. Copy publishable key and secret key from dashboard.

---

## Phase 1: Provision Services

### 1.1 Create Neon Project

```bash
neonctl projects create --name my-saas-app --region-id aws-us-east-1 --output json
# Save the project ID and connection string from output

# Set context for subsequent commands
neonctl set-context --project-id <project-id>

# Get connection string
neonctl connection-string
```

Add to `.env.local`:
```env
DATABASE_URL=postgresql://neondb_owner:<password>@ep-xxx.us-east-1.aws.neon.tech/neondb?sslmode=require
```

### 1.2 Clerk Keys

**🚧 HUMAN GATE:** Copy from clerk.com dashboard:

```env
NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY=pk_test_...
CLERK_SECRET_KEY=sk_test_...
NEXT_PUBLIC_CLERK_SIGN_IN_URL=/sign-in
NEXT_PUBLIC_CLERK_SIGN_UP_URL=/sign-up
```

### 1.3 Stripe Keys

**🚧 HUMAN GATE:** Copy from dashboard.stripe.com/apikeys:

```env
NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY=pk_test_...
STRIPE_SECRET_KEY=sk_test_...
```

### 1.4 Initial Vercel Deploy

```bash
vercel --yes
# Save deployment URL
```

### Verification: Phase 1

```bash
# Neon
neonctl sql "SELECT version();" && echo "Neon: ✅"

# Vercel
curl -s -o /dev/null -w "Vercel: HTTP %{http_code}\n" "https://<deployment-url>"

# Stripe
stripe config --list | grep "test mode" && echo "Stripe: ✅"
```

---

## Phase 2: Database Schema

With Neon, you can run SQL directly via the CLI:

```bash
# Create migration file locally
mkdir -p db/migrations

cat > db/migrations/001_initial.sql << 'EOF'
-- User profiles (linked to Clerk user IDs)
CREATE TABLE profiles (
  id TEXT PRIMARY KEY,  -- Clerk user_xxx ID
  email TEXT,
  full_name TEXT,
  stripe_customer_id TEXT UNIQUE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Subscriptions (synced from Stripe)
CREATE TABLE subscriptions (
  id TEXT PRIMARY KEY,  -- Stripe sub_xxx
  user_id TEXT REFERENCES profiles(id) ON DELETE CASCADE,
  status TEXT NOT NULL,
  price_id TEXT,
  current_period_start TIMESTAMPTZ,
  current_period_end TIMESTAMPTZ,
  cancel_at_period_end BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Products and Prices (synced from Stripe)
CREATE TABLE products (
  id TEXT PRIMARY KEY,
  name TEXT,
  description TEXT,
  active BOOLEAN DEFAULT TRUE
);

CREATE TABLE prices (
  id TEXT PRIMARY KEY,
  product_id TEXT REFERENCES products(id),
  unit_amount BIGINT,
  currency TEXT,
  interval TEXT,
  active BOOLEAN DEFAULT TRUE
);
EOF

# Push to Neon
neonctl sql --file db/migrations/001_initial.sql
```

**Key difference from Supabase:** No RLS policies — Neon is plain Postgres. Auth is handled by Clerk at the application layer, not the database layer. Your API routes check `auth().userId` and filter queries accordingly.

### Verification: Phase 2

```bash
neonctl sql "SELECT table_name FROM information_schema.tables WHERE table_schema='public';"
# Should show: profiles, subscriptions, products, prices
```

---

## Phase 3: Cross-Service Wiring

### 3.1 Clerk Middleware

Create `middleware.ts` in your project root — see `references/services/clerk.md` for the full pattern.

### 3.2 Stripe Products + Webhooks

Same as golden path — see `references/services/stripe.md`:

```bash
# Create product
stripe products create --name="Pro Plan" --description="Full access"

# Create price
stripe prices create --product=prod_... --unit-amount=2900 --currency=usd \
  -d "recurring[interval]=month"

# Create webhook endpoint
stripe webhook_endpoints create \
  --url="https://<deployment-url>/api/webhooks/stripe" \
  --enabled-events="checkout.session.completed" \
  --enabled-events="customer.subscription.created" \
  --enabled-events="customer.subscription.updated" \
  --enabled-events="customer.subscription.deleted"
# Save whsec_...
```

### 3.3 Clerk → Stripe User Sync

Since Clerk manages users (not Supabase Auth), you need to sync Clerk users to your database and Stripe. Common pattern using Clerk webhooks:

**🚧 HUMAN GATE:** In Clerk Dashboard → Webhooks, add endpoint `https://<deployment-url>/api/webhooks/clerk` with events:
- `user.created`
- `user.updated`
- `user.deleted`

Copy the webhook signing secret.

Add to `.env.local`:
```env
CLERK_WEBHOOK_SECRET=whsec_...
```

### Verification: Phase 3

```bash
# Stripe
stripe webhook_endpoints list
stripe products list --limit=5

# Test Clerk auth (manual — sign up in app)
echo "Sign up at https://<deployment-url>/sign-up to verify Clerk"
```

---

## Phase 4: Env Var Sync to Vercel

```bash
# Clerk
vercel env add NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY production preview development <<< "pk_test_..."
vercel env add CLERK_SECRET_KEY production <<< "sk_test_..."
vercel env add NEXT_PUBLIC_CLERK_SIGN_IN_URL production preview development <<< "/sign-in"
vercel env add NEXT_PUBLIC_CLERK_SIGN_UP_URL production preview development <<< "/sign-up"
vercel env add CLERK_WEBHOOK_SECRET production <<< "whsec_..."

# Neon
vercel env add DATABASE_URL production <<< "postgresql://..."

# Stripe
vercel env add NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY production preview development <<< "pk_test_..."
vercel env add STRIPE_SECRET_KEY production <<< "sk_test_..."
vercel env add STRIPE_WEBHOOK_SECRET production <<< "whsec_..."

# App URL
vercel env add NEXT_PUBLIC_APP_URL production <<< "https://<your-domain>"

# Redeploy
vercel --prod --yes
```

---

## Phase 5: Verification

```bash
echo "=== Stack Verification ==="

# Neon
neonctl sql "SELECT 1 AS health;" && echo "Neon DB: ✅" || echo "Neon DB: ❌"

# Tables
neonctl sql "SELECT count(*) FROM profiles;" && echo "Profiles table: ✅" || echo "Profiles table: ❌"

# Vercel
VERCEL_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "https://<deployment-url>")
echo "Vercel: HTTP $VERCEL_STATUS $([ '$VERCEL_STATUS' = '200' ] && echo '✅' || echo '❌')"

# Stripe
PRODUCTS=$(stripe products list --limit=1 -o json 2>/dev/null | grep -c '"id"')
echo "Stripe products: $([ $PRODUCTS -gt 0 ] && echo '✅' || echo '❌')"

WEBHOOKS=$(stripe webhook_endpoints list 2>/dev/null | grep -c '"url"')
echo "Stripe webhooks: $([ $WEBHOOKS -gt 0 ] && echo '✅' || echo '❌')"

echo "=== Done ==="
```

---

## Key Differences from Golden Path (Supabase)

| Concern | Supabase Stack | Clerk + Neon Stack |
|---|---|---|
| Auth | Supabase Auth (DB-level, RLS) | Clerk (app-level, middleware) |
| Database | Supabase Postgres (managed) | Neon Postgres (serverless, branching) |
| Security model | RLS policies in SQL | Application-level auth checks |
| User sync | Auto via trigger on auth.users | Manual via Clerk webhooks |
| Pre-built UI | Limited (email/password form) | Rich (sign-in, user profile, org switcher) |
| Branching | Supabase branching (beta) | Neon branching (mature, per-PR) |
| Cost at scale | $25/mo Pro | Neon free tier generous, Clerk free to 10K MAUs |
