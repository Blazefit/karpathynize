# Service Reference: Clerk

Clerk provides authentication, user management, and organization/multi-tenancy features with pre-built UI components.

## Setup

```bash
# Install SDK (no standalone CLI — Clerk is SDK + Dashboard driven)
npm install @clerk/nextjs
```

**🚧 HUMAN GATE:** Create account and application at clerk.com. Get API keys from the dashboard.

Clerk uses two keys:
- `NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY` (pk_test_... or pk_live_...) — client-side
- `CLERK_SECRET_KEY` (sk_test_... or sk_live_...) — server-side

Add to `.env.local`:
```env
NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY=pk_test_...
CLERK_SECRET_KEY=sk_test_...
NEXT_PUBLIC_CLERK_SIGN_IN_URL=/sign-in
NEXT_PUBLIC_CLERK_SIGN_UP_URL=/sign-up
NEXT_PUBLIC_CLERK_SIGN_IN_FALLBACK_REDIRECT_URL=/dashboard
NEXT_PUBLIC_CLERK_SIGN_UP_FALLBACK_REDIRECT_URL=/dashboard
```

## App Integration (Next.js App Router)

Clerk requires wrapping your app in `<ClerkProvider>`:

```typescript
// app/layout.tsx
import { ClerkProvider } from '@clerk/nextjs'

export default function RootLayout({ children }) {
  return (
    <ClerkProvider>
      <html><body>{children}</body></html>
    </ClerkProvider>
  )
}
```

Add middleware for route protection:
```typescript
// middleware.ts
import { clerkMiddleware, createRouteMatcher } from '@clerk/nextjs/server'

const isPublicRoute = createRouteMatcher(['/sign-in(.*)', '/sign-up(.*)', '/'])

export default clerkMiddleware(async (auth, request) => {
  if (!isPublicRoute(request)) {
    await auth.protect()
  }
})

export const config = {
  matcher: ['/((?!.*\\..*|_next).*)', '/', '/(api|trpc)(.*)'],
}
```

## Clerk Backend API (for automation)

Clerk has a REST API for managing users, organizations, and sessions:

```bash
# List users
curl -X GET "https://api.clerk.com/v1/users?limit=10" \
  -H "Authorization: Bearer sk_test_..."

# Get user by ID
curl -X GET "https://api.clerk.com/v1/users/user_..." \
  -H "Authorization: Bearer sk_test_..."

# Create organization
curl -X POST "https://api.clerk.com/v1/organizations" \
  -H "Authorization: Bearer sk_test_..." \
  -H "Content-Type: application/json" \
  -d '{"name": "My Company", "created_by": "user_..."}'
```

## OAuth Provider Setup

**🚧 HUMAN GATE:** OAuth providers (Google, GitHub) must be configured in:
1. The provider's developer console (create OAuth app)
2. Clerk Dashboard → User & Authentication → Social Connections

The redirect URL pattern for Clerk is:
- Development: `https://YOUR_CLERK_FRONTEND_API/v1/oauth_callback`
- The exact URL is shown in the Clerk Dashboard when you enable a provider.

## Wiring with Vercel

```bash
vercel env add NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY production preview development <<< "pk_test_..."
vercel env add CLERK_SECRET_KEY production <<< "sk_test_..."
vercel env add NEXT_PUBLIC_CLERK_SIGN_IN_URL production preview development <<< "/sign-in"
vercel env add NEXT_PUBLIC_CLERK_SIGN_UP_URL production preview development <<< "/sign-up"
```

## Wiring with Stripe (syncing user → customer)

Clerk doesn't natively sync with Stripe. Common pattern: use a webhook or server action to create a Stripe customer when a Clerk user signs up, store `stripe_customer_id` in Clerk user metadata:

```typescript
import { clerkClient } from '@clerk/nextjs/server'

// After creating Stripe customer:
await clerkClient.users.updateUserMetadata(userId, {
  privateMetadata: { stripeCustomerId: customer.id }
})
```

## Wiring with Database (Neon, Supabase, etc.)

Clerk handles auth; your database stores app data. Connect them via Clerk's `userId`:
- Every authenticated request has `auth().userId`
- Use this as the foreign key in your database tables
- No JWT/RLS integration like Supabase Auth — you query the DB with the userId directly

## Test vs. Production

- Development instance: `pk_test_` / `sk_test_` keys, free up to 10,000 MAUs
- Production instance: `pk_live_` / `sk_live_` keys, separate user database

**🚧 HUMAN GATE:** Switching to production requires creating a production instance in the Clerk Dashboard and re-configuring DNS/domains.

## Failure Modes

| Error | Cause | Fix |
|---|---|---|
| `@clerk/nextjs: Missing publishableKey` | Env var not set | Add `NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY` |
| 401 on API routes | Middleware not configured | Add `middleware.ts` |
| OAuth redirect fails | Redirect URL not configured in provider | Check Clerk Dashboard → Social Connections |
| `clerk: unable to verify session` | Clock skew or wrong secret key | Check `CLERK_SECRET_KEY` |
