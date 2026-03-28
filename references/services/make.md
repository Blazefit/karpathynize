# Service Reference: Make (formerly Integromat)

Make is a visual workflow automation platform with 1500+ app integrations. It's the most popular no-code/low-code automation tool after Zapier, with more powerful data transformation capabilities. Make is cloud-only (no self-hosting).

## Account Setup

**🚧 HUMAN GATE:** Create account at make.com. Free tier includes 1,000 operations/month.

## API Access

Make has a comprehensive REST API for managing scenarios (workflows), connections, and executions.

```bash
# Base URL: https://us1.make.com/api/v2 (or eu1/eu2 depending on region)
# Auth: API token (create in Make > Profile > API)

# List all scenarios
curl -s "https://us1.make.com/api/v2/scenarios?teamId=<team-id>" \
  -H "Authorization: Token <api-token>" | jq

# Get scenario detail
curl -s "https://us1.make.com/api/v2/scenarios/<scenario-id>" \
  -H "Authorization: Token <api-token>" | jq

# Activate a scenario
curl -X PATCH "https://us1.make.com/api/v2/scenarios/<scenario-id>" \
  -H "Authorization: Token <api-token>" \
  -H "Content-Type: application/json" \
  -d '{"scheduling": {"type": "immediately"}}'

# Deactivate a scenario
curl -X PATCH "https://us1.make.com/api/v2/scenarios/<scenario-id>" \
  -H "Authorization: Token <api-token>" \
  -H "Content-Type: application/json" \
  -d '{"scheduling": {"type": "indefinitely"}}'

# Run a scenario immediately
curl -X POST "https://us1.make.com/api/v2/scenarios/<scenario-id>/run" \
  -H "Authorization: Token <api-token>"

# List scenario executions
curl -s "https://us1.make.com/api/v2/scenarios/<scenario-id>/logs?limit=10" \
  -H "Authorization: Token <api-token>" | jq

# List teams (to get team ID)
curl -s "https://us1.make.com/api/v2/teams" \
  -H "Authorization: Token <api-token>" | jq
```

## Webhook Integration

Make scenarios can be triggered via webhooks from your app.

### Creating a Webhook in Make

```
1. In Make, create a new scenario
2. Add "Webhooks" > "Custom webhook" as the trigger
3. Make generates a unique webhook URL:
   https://hook.us1.make.com/abcdef123456...
4. Copy this URL to use in your app
```

### Calling Make Webhooks from Your App

```typescript
// In your Next.js app — trigger a Make scenario
const response = await fetch('https://hook.us1.make.com/<webhook-id>', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({
    event: 'user.signup',
    userId: user.id,
    email: user.email,
    plan: 'pro',
  }),
});

// Make returns the scenario result if configured to respond
const result = await response.json();
```

### Webhook Response Mode

Make webhooks can operate in two modes:
- **Immediately (default):** Returns 200 OK immediately, processes asynchronously
- **Response:** Waits for scenario to complete and returns a custom response

For the response mode, add a "Webhook response" module at the end of your scenario.

## Common Automation Patterns

### Stripe Events → Make → Multi-Service

```
Stripe Webhook → Make Custom Webhook
  ├→ Route by event type (router module)
  │  ├→ checkout.session.completed
  │  │  ├→ Update Supabase (HTTP module or Supabase app)
  │  │  ├→ Send welcome email (Gmail/Resend)
  │  │  └→ Add to CRM (HubSpot/Airtable)
  │  ├→ invoice.payment_failed
  │  │  ├→ Send dunning email
  │  │  └→ Create support ticket
  │  └→ customer.subscription.deleted
  │     ├→ Update user status in DB
  │     └→ Send cancellation survey
```

### Scheduled Data Sync

```
Schedule trigger (daily at 9am)
  → Fetch data from API (HTTP module)
  → Transform data (JSON/Array modules)
  → Update Google Sheet
  → Send Slack summary
```

### Form → CRM → Email Sequence

```
Custom Webhook (form submission)
  → Create/update HubSpot contact
  → Add to email sequence
  → Notify sales team in Slack
  → Log to Google Sheet
```

## Make vs n8n Comparison

| Feature | Make | n8n |
|---|---|---|
| Hosting | Cloud-only | Self-hosted or cloud |
| Integrations | 1500+ built-in | 400+ built-in + custom |
| Pricing | Operations-based | Free (self-hosted) or executions-based |
| Data transform | Visual, powerful | Code-based, flexible |
| API | Comprehensive REST | REST + CLI |
| Open source | No | Yes |
| Best for | Non-technical teams, complex visual workflows | Developers, data-heavy automations |

## Wiring Make to Your Stack

### Connect to Supabase
```
Use Make's HTTP module (Supabase doesn't have a native Make app):
  URL: https://xxx.supabase.co/rest/v1/<table>
  Headers:
    apikey: <anon-key>
    Authorization: Bearer <service-role-key>
    Content-Type: application/json
```

### Connect to Stripe
```
Make has a native Stripe app:
  1. Add Stripe connection in Make
  2. Enter Secret Key (sk_test_... or sk_live_...)
  3. Use Stripe trigger module for events
  4. Or Stripe action modules for creating charges, subscriptions, etc.
```

### Connect to Linear
```
Use Make's HTTP module with Linear's GraphQL API:
  URL: https://api.linear.app/graphql
  Headers:
    Authorization: <linear-api-key>
    Content-Type: application/json
  Body: GraphQL mutation/query
```

## Required Environment Variables

```bash
# For API access from your app
MAKE_API_TOKEN=               # API token from Make profile
MAKE_TEAM_ID=                 # Team ID (get from API)
MAKE_REGION=us1               # us1, eu1, or eu2

# Webhook URLs (per scenario — store as env vars for your app)
MAKE_WEBHOOK_USER_SIGNUP=https://hook.us1.make.com/...
MAKE_WEBHOOK_PAYMENT_EVENT=https://hook.us1.make.com/...
```

## Dependency Position

- **Depends on:** Nothing (cloud service). Your app needs a deployment URL if Make needs to call back.
- **Depended on by:** Apps that offload async workflows.
- **Layer 1:** Create account, set up API token.
- **Layer 3:** Create scenarios, wire webhook URLs into your app's env vars.
- **Key insight:** Make replaces glue code between services. Instead of writing custom integrations, you build visual workflows that connect services. Best for non-technical teams or when you need 10+ service connections.

## Failure Modes

| Error | Cause | Fix |
|---|---|---|
| Webhook returns 404 | Scenario not active | Activate the scenario in Make |
| `Accepted` but no execution | Scenario has errors | Check execution history in Make for error details |
| Operations limit reached | Hit free tier limit | Upgrade plan or reduce scenario frequency |
| Connection expired | OAuth token expired | Re-authenticate the connection in Make |
| Data mapping error | Unexpected payload structure | Check webhook test data matches actual payload |
| Rate limit (API) | Too many API calls | Make API has per-minute limits — add delays |
