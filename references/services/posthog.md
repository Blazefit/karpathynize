# Service Reference: PostHog

PostHog provides product analytics, session recording, feature flags, A/B testing, and surveys. Self-hostable or cloud.

## Setup

```bash
# Install JS SDK
npm install posthog-js

# For server-side (Next.js API routes)
npm install posthog-node
```

**🚧 HUMAN GATE:** Create account at posthog.com. Get project API key from Settings → Project → API Key.

PostHog uses one client-side key:
```env
NEXT_PUBLIC_POSTHOG_KEY=phc_...
NEXT_PUBLIC_POSTHOG_HOST=https://us.i.posthog.com
# EU: https://eu.i.posthog.com
```

## App Integration (Next.js)

```typescript
// app/providers.tsx
'use client'
import posthog from 'posthog-js'
import { PostHogProvider } from 'posthog-js/react'
import { useEffect } from 'react'

export function PHProvider({ children }: { children: React.ReactNode }) {
  useEffect(() => {
    posthog.init(process.env.NEXT_PUBLIC_POSTHOG_KEY!, {
      api_host: process.env.NEXT_PUBLIC_POSTHOG_HOST,
      capture_pageview: true,
    })
  }, [])
  return <PostHogProvider client={posthog}>{children}</PostHogProvider>
}

// app/layout.tsx — wrap children in <PHProvider>
```

## Wiring with Vercel

```bash
vercel env add NEXT_PUBLIC_POSTHOG_KEY production preview development <<< "phc_..."
vercel env add NEXT_PUBLIC_POSTHOG_HOST production preview development <<< "https://us.i.posthog.com"
```

No webhook or backend wiring needed. PostHog is fire-and-forget client-side analytics.

## Feature Flags (API)

```bash
# Evaluate a flag via API
curl -X POST "https://us.i.posthog.com/decide/?v=3" \
  -H "Content-Type: application/json" \
  -d '{
    "api_key": "phc_...",
    "distinct_id": "user_123"
  }'
```

## Verify Installation

```bash
# Check if PostHog is receiving events
curl -s "https://us.i.posthog.com/api/projects/@current/events/?limit=1" \
  -H "Authorization: Bearer phx_..." \
  -o /dev/null -w "PostHog API: HTTP %{http_code}\n"
```

**Note:** The personal API key (phx_...) for API access is different from the project API key (phc_...) used for event capture. Get the personal key from PostHog → Settings → Personal API Keys.

## Failure Modes

| Error | Cause | Fix |
|---|---|---|
| No events appearing | Wrong API key or host | Verify `NEXT_PUBLIC_POSTHOG_KEY` and host region |
| Ad blockers blocking PostHog | Client sends to posthog.com | Set up reverse proxy or use `us.i.posthog.com` |
| `posthog.init is not a function` | SSR context (no window) | Ensure init runs only in `useEffect` (client-side) |
