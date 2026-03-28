# Service Reference: n8n

n8n is an open-source workflow automation platform (self-hostable alternative to Zapier/Make). It connects services via visual workflows with 400+ integrations. Can be self-hosted or used via n8n.cloud.

## Deployment Options

### Option A: n8n Cloud (managed)
**🚧 HUMAN GATE:** Sign up at n8n.cloud. Free tier available. No CLI needed — all config via web UI or API.

### Option B: Self-Hosted (Docker)

```bash
# Quick start with Docker
docker run -d \
  --name n8n \
  -p 5678:5678 \
  -v n8n_data:/home/node/.n8n \
  -e N8N_BASIC_AUTH_ACTIVE=true \
  -e N8N_BASIC_AUTH_USER=admin \
  -e N8N_BASIC_AUTH_PASSWORD=<password> \
  n8nio/n8n

# With persistent SQLite (default) at http://localhost:5678
```

### Option C: Self-Hosted on Railway

```bash
# Deploy to Railway (one-click if you have Railway CLI)
# See references/services/railway.md for Railway setup

# Railway template for n8n:
railway init --template n8n
railway up

# Set environment variables
railway variables set N8N_BASIC_AUTH_ACTIVE=true
railway variables set N8N_BASIC_AUTH_USER=admin
railway variables set N8N_BASIC_AUTH_PASSWORD=<password>
railway variables set WEBHOOK_URL=https://your-n8n.railway.app/
```

### Option D: Self-Hosted on Docker Compose (Production)

```yaml
# docker-compose.yml
version: '3.8'
services:
  n8n:
    image: n8nio/n8n
    ports:
      - "5678:5678"
    environment:
      - N8N_BASIC_AUTH_ACTIVE=true
      - N8N_BASIC_AUTH_USER=admin
      - N8N_BASIC_AUTH_PASSWORD=${N8N_PASSWORD}
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=postgres
      - DB_POSTGRESDB_DATABASE=n8n
      - DB_POSTGRESDB_USER=n8n
      - DB_POSTGRESDB_PASSWORD=${POSTGRES_PASSWORD}
      - WEBHOOK_URL=https://your-n8n-domain.com/
      - N8N_ENCRYPTION_KEY=${ENCRYPTION_KEY}
    volumes:
      - n8n_data:/home/node/.n8n
    depends_on:
      - postgres

  postgres:
    image: postgres:16
    environment:
      - POSTGRES_DB=n8n
      - POSTGRES_USER=n8n
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
    volumes:
      - postgres_data:/var/lib/postgresql/data

volumes:
  n8n_data:
  postgres_data:
```

## API Access

n8n exposes a REST API for managing workflows, executions, and credentials programmatically.

```bash
# Base URL: https://your-n8n-instance.com/api/v1
# Auth: API key (create in n8n Settings > API)

# List all workflows
curl -s "https://your-n8n.com/api/v1/workflows" \
  -H "X-N8N-API-KEY: <api-key>" | jq

# Get a specific workflow
curl -s "https://your-n8n.com/api/v1/workflows/<workflow-id>" \
  -H "X-N8N-API-KEY: <api-key>" | jq

# Activate a workflow
curl -X PATCH "https://your-n8n.com/api/v1/workflows/<workflow-id>" \
  -H "X-N8N-API-KEY: <api-key>" \
  -H "Content-Type: application/json" \
  -d '{"active": true}'

# Deactivate a workflow
curl -X PATCH "https://your-n8n.com/api/v1/workflows/<workflow-id>" \
  -H "X-N8N-API-KEY: <api-key>" \
  -H "Content-Type: application/json" \
  -d '{"active": false}'

# List executions
curl -s "https://your-n8n.com/api/v1/executions?limit=10" \
  -H "X-N8N-API-KEY: <api-key>" | jq

# Trigger a workflow via webhook
# (workflow must have a Webhook trigger node)
curl -X POST "https://your-n8n.com/webhook/<webhook-path>" \
  -H "Content-Type: application/json" \
  -d '{"event": "user.created", "data": {"userId": "123"}}'
```

## CLI (n8n command line)

```bash
# Install globally (for self-hosted management)
npm install -g n8n

# Start n8n
n8n start

# Execute a workflow from CLI
n8n execute --id=<workflow-id>

# Export all workflows
n8n export:workflow --all --output=workflows/

# Export a specific workflow
n8n export:workflow --id=<workflow-id> --output=workflow.json

# Import a workflow
n8n import:workflow --input=workflow.json

# Export credentials (encrypted)
n8n export:credentials --all --output=credentials/

# Import credentials
n8n import:credentials --input=credentials.json
```

## Webhook Integration Patterns

n8n workflows are triggered by webhooks from your app. Common patterns:

### Stripe → n8n → Supabase/Email
```
Your App → Stripe Webhook → n8n Webhook Node
  → Filter by event type
  → Update Supabase (via Supabase node)
  → Send email (via Resend/SendGrid node)
  → Post to Slack
```

### GitHub → n8n → Linear
```
GitHub Webhook (PR merged) → n8n
  → Create Linear issue for deployment tracking
  → Notify Slack channel
  → Update status page
```

### Form Submission → n8n → CRM + Email
```
Your App (form POST) → n8n Webhook
  → Add to CRM (HubSpot/Airtable node)
  → Send welcome email (Resend node)
  → Add to mailing list (Mailchimp node)
```

## Wiring n8n to Your Stack

### Connect n8n to Supabase
```
In n8n: Add Supabase credentials
  - Supabase URL: https://xxx.supabase.co
  - Service Role Key: (from your .env)

Use the Supabase node to:
  - Insert/update/delete rows
  - Listen to database changes (via webhooks from your app)
```

### Connect n8n to Stripe
```
In n8n: Add Stripe credentials
  - Secret Key: sk_test_...

Stripe Trigger node listens for events directly
(no need to configure webhooks manually — n8n handles it)
```

### Connect n8n to your app via webhooks
```bash
# Your app sends events to n8n:
# POST https://your-n8n.com/webhook/<webhook-path>

# In your Next.js app:
await fetch('https://your-n8n.com/webhook/user-signup', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ userId, email, plan }),
});
```

## Required Environment Variables

```bash
# n8n instance
N8N_HOST=https://your-n8n.com
N8N_API_KEY=                    # For API access from your app

# Self-hosted config
N8N_BASIC_AUTH_ACTIVE=true
N8N_BASIC_AUTH_USER=admin
N8N_BASIC_AUTH_PASSWORD=
N8N_ENCRYPTION_KEY=             # For encrypting stored credentials
WEBHOOK_URL=https://your-n8n.com/  # Public URL for webhook triggers
```

## Dependency Position

- **Depends on:** A hosting platform (Railway, Docker host, VPS) if self-hosted. Nothing if using n8n.cloud.
- **Depended on by:** Apps that offload async workflows (email sequences, data sync, notifications).
- **Layer 1:** Deploy n8n instance (cloud or self-hosted).
- **Layer 3:** Wire webhook URLs from your app to n8n, configure n8n credentials for each service it connects to.
- **Key insight:** n8n replaces custom webhook handler code. Instead of writing a Stripe webhook handler in your Next.js app, you point Stripe webhooks at n8n, which handles the routing and side effects visually.

## Failure Modes

| Error | Cause | Fix |
|---|---|---|
| Webhook returns 404 | Workflow not active or wrong path | Activate the workflow, check webhook URL |
| `ECONNREFUSED` on self-hosted | n8n not running or wrong port | Check Docker container status, port mapping |
| Credentials error in workflow | Stored credentials expired or wrong | Update credentials in n8n Settings |
| Execution timeout | Workflow takes too long | Increase timeout in Settings or optimize workflow |
| Webhook URL not accessible | n8n behind firewall or no public URL | Use `WEBHOOK_URL` env var, ensure public access |
| `encryption key` error | Missing N8N_ENCRYPTION_KEY | Set it and don't change it after initial setup |
