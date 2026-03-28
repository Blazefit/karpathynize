# Blueprint: Next.js + Supabase + Stripe + Vercel

The canonical indie SaaS stack. This blueprint takes you from zero to a deployed app with auth, database, payments, and hosting — entirely from the command line.

**Services:** Supabase (auth + database), Stripe (payments), Vercel (hosting), Next.js (framework)
**Total time:** ~30 minutes agent-executed, ~5 minutes human gates
**Prerequisites:** Node.js 18+, npm/pnpm, Git

---

## Phase -1: Project Scaffolding (skip if you already have a codebase)

If starting from zero with no existing code:

```bash
# Create Next.js app with TypeScript and Tailwind
npx create-next-app@latest my-saas-app \
  --typescript --tailwind --eslint --app --src-dir --import-alias "@/*"

cd my-saas-app

# Initialize git if not already
git init && git add -A && git commit -m "Initial Next.js scaffold"

# Install core dependencies for the SaaS stack
npm install @supabase/supabase-js @supabase/ssr stripe @stripe/stripe-js

# Optional but recommended
npm install resend  # if using email
```

This gives you a working Next.js app that you can deploy immediately (even before adding any features). The key insight: **deploy the skeleton first**, then wire services, then add features. Don't wait until the app is "ready" to deploy.

---

## Phase 0: Prerequisites & CLI Setup

Before anything else, ensure all CLIs are installed and authenticated.

### 0.1 Install CLIs

```bash
# Supabase CLI
npm install -g supabase

# Vercel CLI
npm install -g vercel

# Stripe CLI (macOS)
brew install stripe/stripe-cli/stripe
# Or download from https://github.com/stripe/stripe-cli/releases

# Check installations
supabase --version
vercel --version
stripe --version
```

### 0.2 Authenticate CLIs

```bash
# Supabase — opens browser for OAuth, returns access token
supabase login

# Vercel — opens browser for OAuth
vercel login

# Stripe — opens browser for OAuth
stripe login
```

**🚧 HUMAN GATE:** First-time Stripe account creation requires identity verification in browser. If the user doesn't have a Stripe account yet, direct them to dashboard.stripe.com to create one first. This is a one-time operation.

### 0.3 Check for Stripe Projects (optional accelerator)

```bash
# Check if Stripe Projects plugin is available
stripe projects --help 2>/dev/null
if [ $? -eq 0 ]; then
  echo "STRIPE_PROJECTS_AVAILABLE=true"
else
  echo "STRIPE_PROJECTS_AVAILABLE=false"
fi
```

If available, see Phase 1A. If not, proceed to Phase 1B.

---

## Phase 1A: Bulk Provisioning via Stripe Projects

If Stripe Projects is available, use it for streamlined provisioning:

```bash
# Initialize the project
stripe projects init my-saas-app

# Provision all services
stripe projects add supabase/database
stripe projects add vercel/project
# Note: Stripe itself doesn't need "adding" — it's already your Stripe account

# Sync credentials to .env
stripe projects env sync
```

This creates accounts, provisions resources, and syncs API keys into your `.env` file automatically. **Skip to Phase 2** after this.

---

## Phase 1B: Individual Service Provisioning (Stripe Projects not available)

### 1B.1 Create Supabase Project

```bash
# List your organizations to get the org ID
supabase orgs list

# Create project (replace values)
supabase projects create my-saas-app \
  --org-id <your-org-id> \
  --db-password <generate-a-strong-password> \
  --region us-east-1

# The command outputs the project ref. Save it.
# Example output: Created project: abcdefghijklmnop

# Get API keys
supabase projects api-keys --project-ref <project-ref>
# Outputs: anon key, service_role key

# Link local project to remote
supabase link --project-ref <project-ref>
```

**Capture these values into `.env.local`:**
```env
NEXT_PUBLIC_SUPABASE_URL=https://<project-ref>.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=<anon-key>
SUPABASE_SERVICE_ROLE_KEY=<service-role-key>
SUPABASE_DB_PASSWORD=<the-password-you-set>
```

### 1B.2 Get Stripe Keys

```bash
# List available API keys (you must be logged in)
stripe config --list

# For test mode keys, they're in your dashboard but also accessible via:
# The CLI uses your test mode keys by default when logged in
```

**🚧 HUMAN GATE:** Stripe API keys must be copied from dashboard.stripe.com/apikeys. The CLI authenticates via device auth but doesn't expose the raw publishable/secret keys programmatically. Direct the user to copy:
- Publishable key (pk_test_...)
- Secret key (sk_test_...)

Add to `.env.local`:
```env
NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY=pk_test_...
STRIPE_SECRET_KEY=sk_test_...
```

### 1B.3 Deploy Initial Vercel Project

```bash
# Deploy from current directory (creates project if new)
vercel --yes

# The first deploy outputs the deployment URL. Save it.
# Example: https://my-saas-app-abc123.vercel.app

# Get the production domain
vercel inspect <deployment-url> 2>/dev/null | grep "Production"
```

**Capture deployment URL** — you'll need it for webhook configuration in Phase 3.

### Verification: Phase 1

```bash
echo "=== Phase 1 Verification ==="

# Check Supabase is accessible
curl -s "https://<project-ref>.supabase.co/rest/v1/" \
  -H "apikey: <anon-key>" \
  -H "Authorization: Bearer <anon-key>" \
  -o /dev/null -w "Supabase API: HTTP %{http_code}\n"

# Check Vercel deployment is live
curl -s -o /dev/null -w "Vercel deployment: HTTP %{http_code}\n" \
  "https://<deployment-url>"

# Check Stripe connection
stripe config --list | grep "test mode"
echo "Stripe CLI: Connected"
```

**All three should return 200 or show connected status. Do not proceed until verified.**

---

## Phase 2: Database Schema & Auth Setup

This phase runs migrations and configures auth. It has NO external dependencies — only requires a working Supabase project from Phase 1.

### 2.1 Initialize Local Supabase Config

```bash
# If not already done
supabase init
```

### 2.2 Create Database Migrations

Create migration files for your app's schema. At minimum for a SaaS with payments:

```bash
# Create migration file
supabase migration new initial_schema
```

Edit the generated file in `supabase/migrations/` with your schema.

**The schema below is a TEMPLATE for SaaS-with-payments.** It handles the plumbing that every subscription app needs (profiles, subscriptions, products, prices). Replace or extend it with your app's domain-specific tables. The important parts to keep are: the `profiles` table linked to `auth.users`, the Stripe sync tables (`subscriptions`, `products`, `prices`), and the auto-profile-creation trigger.

```sql
-- Users profile (extends Supabase auth.users)
create table public.profiles (
  id uuid references auth.users(id) on delete cascade primary key,
  email text,
  full_name text,
  stripe_customer_id text unique,
  created_at timestamptz default now()
);

-- Enable RLS
alter table public.profiles enable row level security;

-- Users can read/update their own profile
create policy "Users can view own profile"
  on public.profiles for select
  using (auth.uid() = id);

create policy "Users can update own profile"
  on public.profiles for update
  using (auth.uid() = id);

-- Subscriptions (synced from Stripe webhooks)
create table public.subscriptions (
  id text primary key, -- Stripe subscription ID
  user_id uuid references public.profiles(id) on delete cascade,
  status text not null,
  price_id text,
  current_period_start timestamptz,
  current_period_end timestamptz,
  cancel_at_period_end boolean default false,
  created_at timestamptz default now()
);

alter table public.subscriptions enable row level security;

create policy "Users can view own subscriptions"
  on public.subscriptions for select
  using (auth.uid() = user_id);

-- Products and Prices (synced from Stripe)
create table public.products (
  id text primary key, -- Stripe product ID
  name text,
  description text,
  active boolean default true
);

create table public.prices (
  id text primary key, -- Stripe price ID
  product_id text references public.products(id),
  unit_amount bigint,
  currency text,
  interval text, -- 'month', 'year'
  active boolean default true
);

-- Products/prices are public readable
alter table public.products enable row level security;
alter table public.prices enable row level security;

create policy "Products are publicly readable"
  on public.products for select using (true);

create policy "Prices are publicly readable"
  on public.prices for select using (true);

-- Function to auto-create profile on signup
create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id, email, full_name)
  values (
    new.id,
    new.email,
    new.raw_user_meta_data->>'full_name'
  );
  return new;
end;
$$ language plpgsql security definer;

-- Trigger on auth.users insert
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();
```

### 2.3 Push Migrations

```bash
# Push to remote Supabase project
supabase db push

# Verify tables exist
supabase db lint
```

### 2.4 Configure Auth Redirect URLs

```bash
# Update Supabase config to allow redirects to your Vercel URL
# In supabase/config.toml, set:
# [auth]
# site_url = "https://<your-vercel-url>"
# additional_redirect_urls = ["http://localhost:3000", "https://<your-vercel-url>"]

# Push config to remote
supabase config push
```

**Alternative via Management API:**
```bash
curl -X PATCH "https://api.supabase.com/v1/projects/<project-ref>/config/auth" \
  -H "Authorization: Bearer <supabase-access-token>" \
  -H "Content-Type: application/json" \
  -d '{
    "site_url": "https://<your-vercel-url>",
    "uri_allow_list": "http://localhost:3000,https://<your-vercel-url>"
  }'
```

### Verification: Phase 2

```bash
# Check tables exist via Supabase API
curl -s "https://<project-ref>.supabase.co/rest/v1/profiles?select=id&limit=0" \
  -H "apikey: <anon-key>" \
  -H "Authorization: Bearer <anon-key>" \
  -o /dev/null -w "Profiles table: HTTP %{http_code}\n"

curl -s "https://<project-ref>.supabase.co/rest/v1/subscriptions?select=id&limit=0" \
  -H "apikey: <anon-key>" \
  -H "Authorization: Bearer <anon-key>" \
  -o /dev/null -w "Subscriptions table: HTTP %{http_code}\n"

echo "Phase 2: Schema and auth configured"
```

---

## Phase 3: Stripe Configuration & Webhook Wiring

This is the most intricate phase. Stripe needs to send events to your Vercel deployment, and your app needs to sync those events to Supabase. This phase DEPENDS on having a deployment URL from Phase 1.

### 3.1 Create Stripe Products & Prices

```bash
# Create a product
stripe products create \
  --name="Pro Plan" \
  --description="Full access to all features"

# Save the product ID from output (prod_...)

# Create a monthly price
stripe prices create \
  --product=<product-id> \
  --unit-amount=2900 \
  --currency=usd \
  -d "recurring[interval]=month"

# Create an annual price
stripe prices create \
  --product=<product-id> \
  --unit-amount=29000 \
  --currency=usd \
  -d "recurring[interval]=year"

# Save both price IDs (price_...)
```

### 3.2 Create Webhook Endpoint

Your app needs a webhook handler route. The endpoint URL follows the pattern:
`https://<your-vercel-url>/api/webhooks/stripe`

```bash
# Create webhook endpoint listening for key events
stripe webhook_endpoints create \
  --url="https://<your-vercel-url>/api/webhooks/stripe" \
  --enabled-events="checkout.session.completed" \
  --enabled-events="customer.subscription.created" \
  --enabled-events="customer.subscription.updated" \
  --enabled-events="customer.subscription.deleted" \
  --enabled-events="product.created" \
  --enabled-events="product.updated" \
  --enabled-events="price.created" \
  --enabled-events="price.updated"

# The output contains the webhook signing secret (whsec_...)
# SAVE THIS — you need it in your app to verify webhook signatures
```

Add to `.env.local`:
```env
STRIPE_WEBHOOK_SECRET=whsec_...
```

### 3.3 Configure Customer Portal

```bash
# Create a customer portal configuration
stripe billing_portal_configurations create \
  -d "business_profile[headline]=Manage your subscription" \
  -d "features[subscription_cancel][enabled]=true" \
  -d "features[subscription_update][enabled]=true" \
  -d "features[payment_method_update][enabled]=true"
```

### 3.4 Local Webhook Testing (Development)

For local development, use Stripe CLI's webhook forwarding:

```bash
# Forward webhooks to local dev server
stripe listen --forward-to localhost:3000/api/webhooks/stripe

# This prints a LOCAL webhook signing secret (whsec_...)
# Use this in .env.local for local testing (different from prod secret)
```

### Verification: Phase 3

```bash
# List webhook endpoints
stripe webhook_endpoints list

# Trigger a test event
stripe trigger checkout.session.completed

# Check Stripe products exist
stripe products list --limit=5

echo "Phase 3: Stripe configured with webhooks"
```

---

## Phase 4: Environment Variable Sync to Vercel

All secrets must be set in Vercel for the deployed app to work. This is where most people lose hours clicking through dashboards.

### 4.1 Set All Environment Variables

```bash
# Supabase vars
vercel env add NEXT_PUBLIC_SUPABASE_URL production preview development <<< "https://<project-ref>.supabase.co"
vercel env add NEXT_PUBLIC_SUPABASE_ANON_KEY production preview development <<< "<anon-key>"
vercel env add SUPABASE_SERVICE_ROLE_KEY production <<< "<service-role-key>"

# Stripe vars
vercel env add NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY production preview development <<< "pk_test_..."
vercel env add STRIPE_SECRET_KEY production <<< "sk_test_..."
vercel env add STRIPE_WEBHOOK_SECRET production <<< "whsec_..."

# App URL (for auth redirects, absolute URLs in emails, etc.)
vercel env add NEXT_PUBLIC_APP_URL production <<< "https://<your-production-domain>"
vercel env add NEXT_PUBLIC_APP_URL preview <<< "https://<your-vercel-url>"
vercel env add NEXT_PUBLIC_APP_URL development <<< "http://localhost:3000"
```

**Note:** The `vercel env add` command is interactive by default. Use the heredoc `<<<` syntax or pipe to make it non-interactive for agent execution. If that doesn't work in your shell:

```bash
echo "<value>" | vercel env add <VAR_NAME> production
```

### 4.2 Redeploy with Environment Variables

```bash
# Redeploy to pick up new env vars
vercel --prod --yes
```

### Verification: Phase 4

```bash
# List all env vars (names only, not values)
vercel env ls

# Check the production deployment is healthy
PROD_URL=$(vercel inspect --json 2>/dev/null | grep -o '"url":"[^"]*"' | head -1 | cut -d'"' -f4)
curl -s -o /dev/null -w "Production: HTTP %{http_code}\n" "https://$PROD_URL"

echo "Phase 4: Environment synced to Vercel"
```

---

## Phase 5: Domain Configuration (Optional)

If the user has a custom domain:

### 5.1 Add Domain to Vercel

```bash
# Add custom domain
vercel domains add yourdomain.com

# The CLI will output the DNS records needed
# Typically an A record and/or CNAME
```

### 5.2 Configure DNS

**🚧 HUMAN GATE:** DNS configuration depends on the domain registrar. Most registrars don't have CLI tools. Direct the user to:
1. Log into their domain registrar
2. Add the DNS records Vercel specified
3. Wait for propagation (usually 5-60 minutes)

```bash
# Verify DNS propagation
vercel domains inspect yourdomain.com
```

### 5.3 Update Auth Redirect URLs

After domain is configured, update the redirect URLs:

```bash
# Update Supabase auth config with new domain
curl -X PATCH "https://api.supabase.com/v1/projects/<project-ref>/config/auth" \
  -H "Authorization: Bearer <supabase-access-token>" \
  -H "Content-Type: application/json" \
  -d '{
    "site_url": "https://yourdomain.com",
    "uri_allow_list": "http://localhost:3000,https://yourdomain.com,https://<your-vercel-url>"
  }'

# Update Stripe webhook URL
stripe webhook_endpoints update <webhook-endpoint-id> \
  --url="https://yourdomain.com/api/webhooks/stripe"

# Update Vercel env var
echo "https://yourdomain.com" | vercel env add NEXT_PUBLIC_APP_URL production --force
```

---

## Phase 6: Final Verification

Run the complete stack verification:

```bash
echo "==========================================="
echo "  STACK VERIFICATION REPORT"
echo "==========================================="

# 1. Supabase Health
echo ""
echo "--- Supabase ---"
SUPA_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
  "https://<project-ref>.supabase.co/rest/v1/" \
  -H "apikey: <anon-key>")
echo "API Status: HTTP $SUPA_STATUS $([ '$SUPA_STATUS' = '200' ] && echo '✅' || echo '❌')"

# 2. Database Tables
for TABLE in profiles subscriptions products prices; do
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
    "https://<project-ref>.supabase.co/rest/v1/$TABLE?select=count&limit=0" \
    -H "apikey: <anon-key>" \
    -H "Authorization: Bearer <anon-key>")
  echo "Table '$TABLE': HTTP $STATUS $([ '$STATUS' = '200' ] && echo '✅' || echo '❌')"
done

# 3. Vercel Deployment
echo ""
echo "--- Vercel ---"
VERCEL_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "https://<deployment-url>")
echo "Deployment: HTTP $VERCEL_STATUS $([ '$VERCEL_STATUS' = '200' ] && echo '✅' || echo '❌')"

# 4. Stripe
echo ""
echo "--- Stripe ---"
PRODUCTS=$(stripe products list --limit=1 -o json 2>/dev/null | grep -c '"id"')
echo "Products configured: $([ $PRODUCTS -gt 0 ] && echo '✅' || echo '❌')"

WEBHOOKS=$(stripe webhook_endpoints list -o json 2>/dev/null | grep -c '"url"')
echo "Webhooks configured: $([ $WEBHOOKS -gt 0 ] && echo '✅' || echo '❌')"

# 5. Environment Variables
echo ""
echo "--- Vercel Env Vars ---"
for VAR in NEXT_PUBLIC_SUPABASE_URL NEXT_PUBLIC_SUPABASE_ANON_KEY SUPABASE_SERVICE_ROLE_KEY \
           NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY STRIPE_SECRET_KEY STRIPE_WEBHOOK_SECRET; do
  vercel env ls 2>/dev/null | grep -q "$VAR" && echo "$VAR: ✅" || echo "$VAR: ❌"
done

echo ""
echo "==========================================="
echo "  END VERIFICATION"
echo "==========================================="
```

---

## Common Failure Modes

| Symptom | Cause | Fix |
|---|---|---|
| Webhook 401 | Wrong webhook secret in env | Re-copy `whsec_` from Stripe webhook endpoint, redeploy |
| Auth redirect fails | Redirect URL not in Supabase allow list | Update `uri_allow_list` via Management API |
| Supabase 403 on table | RLS policies missing or wrong | Check `supabase db lint`, add policies |
| Vercel 500 | Missing env var | Run `vercel env ls`, compare against checklist |
| Stripe 400 on checkout | Price ID doesn't exist in current mode (test vs live) | Ensure you're using test mode keys with test mode prices |
| `supabase db push` fails | Migration conflict | `supabase db reset` in dev, or `supabase migration repair` |

---

## Switching from Test to Production

When ready to go live:

1. **Stripe:** Get live keys from dashboard.stripe.com/apikeys (pk_live_... / sk_live_...)
2. **Stripe:** Re-create products/prices in live mode (they don't transfer from test)
3. **Stripe:** Create a new webhook endpoint with live URL and live mode events
4. **Vercel:** Update env vars with live Stripe keys and new webhook secret
5. **Supabase:** No change needed (same project, same keys for prod)
6. **Redeploy:** `vercel --prod --yes`

**🚧 HUMAN GATE:** Activating Stripe live mode requires completing business verification in the Stripe dashboard. This cannot be done via CLI.

---

## Adding Services to This Blueprint

The golden path covers Supabase + Stripe + Vercel. To add more services, follow this pattern after completing the core blueprint:

### Adding Resend (Transactional Email)

1. Read `references/services/resend.md`
2. **🚧 HUMAN GATE:** Create account at resend.com, get API key
3. Add to env: `vercel env add RESEND_API_KEY production <<< "re_..."`
4. **🚧 HUMAN GATE:** Add domain at resend.com/domains, configure DNS records
5. Verify: `curl -s https://api.resend.com/domains -H "Authorization: Bearer re_..." | grep verified`
6. Redeploy: `vercel --prod --yes`

### Adding PostHog (Analytics)

1. **🚧 HUMAN GATE:** Create account at posthog.com, get project API key
2. Install: `npm install posthog-js`
3. Add to env: `vercel env add NEXT_PUBLIC_POSTHOG_KEY production preview development <<< "phc_..."`
4. Add to env: `vercel env add NEXT_PUBLIC_POSTHOG_HOST production preview development <<< "https://us.i.posthog.com"`
5. Redeploy: `vercel --prod --yes`
6. No webhook wiring needed — PostHog is fire-and-forget client-side.

### General Pattern for Any New Service

1. Read the service reference file (if available) from `references/services/`
2. Provision: Create account + get API keys (via Stripe Projects if available, else manually)
3. Wire: Add env vars to Vercel, configure any webhooks or redirects
4. Verify: Test the connection with a simple API call
5. Redeploy to pick up new env vars
