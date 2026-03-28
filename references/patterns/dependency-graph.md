# Dependency Graph: Service Wiring Order

## The Core Problem

Services depend on each other in non-obvious ways. You can't configure Stripe webhooks without a deployment URL. You can't set auth redirect URLs without knowing your domain. If you wire things out of order, you get cryptic errors and waste hours debugging.

This document defines the universal dependency rules that apply regardless of which specific services you're using.

## The Dependency Layers

Services fall into five dependency layers. Complete each layer before moving to the next.

```
Layer 0: CLIs & Auth
  ↓
Layer 1: Core Services (database, hosting account)
  ↓
Layer 2: Initial Deployment (get a URL that exists)
  ↓
Layer 3: Cross-Service Wiring (webhooks, redirects, DNS)
  ↓
Layer 4: Verification & Go-Live
```

### Layer 0: CLIs & Auth
Install and authenticate all CLIs. No provisioning yet.
- This is prerequisite-only. No service interacts with another here.
- **Blocking:** Everything. You can't do anything without authenticated CLIs.

### Layer 1: Core Services
Create projects/accounts in each service independently.
- Database creation (Supabase project, Neon database, PlanetScale)
- Payment provider setup (Stripe account, products, prices)
- Auth provider setup (Supabase Auth config, Clerk application)
- Email service setup (Resend domain verification, API key)
- Analytics setup (PostHog project)

**Key insight:** These can be done in parallel. They don't depend on each other yet.

### Layer 2: Initial Deployment
Deploy the app to get a real URL. This URL is the linchpin — many Layer 3 operations need it.
- Deploy to Vercel/Railway/etc. with whatever env vars you have so far
- The app might not fully work yet — that's expected
- The critical output is: **a URL that resolves**

**Key insight:** You need the URL before you can wire webhooks, auth redirects, or CORS.

### Layer 3: Cross-Service Wiring
Now connect services to each other using the deployment URL.
- Stripe webhook → points to `<deployment-url>/api/webhooks/stripe`
- Auth redirect URLs → includes `<deployment-url>` in allow list
- CORS configuration → allows `<deployment-url>` origin
- Domain DNS → points to hosting provider's IP/CNAME
- Email domain verification → DNS records for Resend/SendGrid

**Key insight:** This is where 80% of the pain lives. Each connection is a specific CLI/API call with specific parameters, and they must reference the deployment URL.

### Layer 4: Verification & Go-Live
Test every connection. Redeploy with all env vars set. Run end-to-end smoke test.

## Common Chicken-and-Egg Problems

### Problem: Stripe webhook needs deployment URL, but deployment needs Stripe env vars
**Solution:** Deploy first with just the Stripe API keys (no webhook secret). The app deploys and has a URL. Then create the webhook endpoint pointing to that URL, get the webhook secret, add it to env vars, and redeploy.

### Problem: Auth redirect URL needs to be set before OAuth works, but you don't know the URL yet
**Solution:** For development, use `http://localhost:3000`. For production, deploy first (auth won't work), get the URL, update the redirect config, redeploy. Or use Vercel's `VERCEL_URL` environment variable which is auto-set.

### Problem: Supabase Edge Functions need Stripe secret, but Stripe needs Supabase URL for database sync
**Solution:** These don't actually depend on each other at provisioning time. Set up Supabase first, then Stripe, then wire the webhook handler (which is your app code, not an Edge Function typically).

### Problem: Custom domain needs DNS propagation, but services need the domain to configure
**Solution:** Configure everything with the Vercel auto-generated URL first. Once domain propagates, update all references (auth redirects, webhook URLs, CORS) to the custom domain. Keep the Vercel URL in allow lists as a fallback.

## Service-Specific Dependency Rules

### Supabase
- **Depends on:** Nothing (can be provisioned independently)
- **Depended on by:** Everything (provides database and auth)
- **Provision first:** Always safe to create Supabase project early

### Vercel
- **Depends on:** Git repo (must exist), env vars (for full functionality)
- **Depended on by:** Webhooks, auth redirects, CORS
- **Deploy early:** Even a broken deploy gives you a URL to wire other services to

### Stripe
- **Depends on:** Vercel URL (for webhooks)
- **Depended on by:** App functionality (payments)
- **Products first:** Create products/prices before webhooks — they're independent of your app URL

### Resend
- **Depends on:** DNS access (for domain verification)
- **Depended on by:** Email functionality
- **Can be last:** Email is often non-critical for initial launch

### PostHog / Analytics
- **Depends on:** Nothing
- **Depended on by:** Nothing (fire-and-forget integration)
- **Can be last:** Lowest priority in the wiring sequence

### Cloudflare
- **Depends on:** Domain (for DNS management), nothing for Workers/D1/R2/KV
- **Depended on by:** Apps using Pages for hosting, Workers for serverless
- **Layer 1:** Create D1 databases, R2 buckets, KV namespaces (all independent)
- **Layer 2:** Deploy to Pages for a URL
- **Layer 3:** Wire DNS, custom domains, webhook Workers
- **Alternative to:** Vercel (for hosting), Neon/Supabase (D1 can replace for edge-first apps)

### Firebase
- **Depends on:** Nothing (auto-creates GCP project)
- **Depended on by:** Apps using Firebase Auth, Firestore, or Hosting
- **Layer 1:** Create project, configure auth providers (🚧 human gate for provider config)
- **Layer 2:** Deploy to Firebase Hosting for a URL
- **Layer 3:** Wire auth redirect domains, function triggers, storage CORS
- **Alternative to:** Supabase (similar full-stack offering, different tradeoffs: Firebase = NoSQL + Google ecosystem, Supabase = PostgreSQL + open source)

### GitHub OAuth
- **Depends on:** Deployment URL (for callback URL). Auth provider (Supabase/Clerk/NextAuth) must exist first.
- **Depended on by:** Auth flow ("Sign in with GitHub")
- **Layer 1:** Create OAuth App (🚧 human gate — browser required)
- **Layer 3:** Wire Client ID + Secret into auth provider, set callback URL to deployment
- **Key chicken-and-egg:** OAuth App callback URL needs the deployment URL. Create the app with `localhost:3000` first, deploy, then update callback URL.

### Linear
- **Depends on:** Deployment URL (for webhooks). Nothing for API access.
- **Depended on by:** DevOps workflows, project sync, status dashboards
- **Layer 1:** Create API key, set up labels/project structure
- **Layer 2:** Deploy app (needed for webhook URL)
- **Layer 3:** Wire webhooks to deployment URL
- **Note:** Webhooks are team-scoped. Create one per team you want to track.

## The Golden Rule

**When in doubt, deploy first.** A broken deployment that gives you a URL is more useful than a perfect local setup with no URL. You can always redeploy after fixing things, but you can't configure webhooks and redirects without a URL.
