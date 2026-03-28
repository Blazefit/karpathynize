# Service Reference: Cloudflare

Cloudflare provides DNS, CDN, Workers (serverless functions), Pages (static/SSR hosting), R2 (object storage), D1 (SQLite at the edge), and KV (key-value storage).

## CLI Authentication

```bash
# Install Wrangler (Cloudflare's CLI)
npm install -g wrangler

# Login (opens browser)
wrangler login

# Login with API token (non-interactive, for agents)
export CLOUDFLARE_API_TOKEN=<api-token>
# Wrangler uses this env var automatically

# Verify authentication
wrangler whoami
```

**Getting an API token:** 🚧 HUMAN GATE — Create at dash.cloudflare.com/profile/api-tokens. Use the "Edit Cloudflare Workers" template for Workers/Pages, or create a custom token with specific permissions. API tokens are scoped (unlike the legacy Global API Key which has full access — avoid using it).

## Pages (Static & SSR Hosting)

```bash
# Create a Pages project from a directory
wrangler pages project create <project-name>

# Deploy a directory
wrangler pages deploy <build-output-dir> --project-name=<project-name>
# Output: https://<project-name>.pages.dev

# Deploy to production branch
wrangler pages deploy <build-output-dir> --project-name=<project-name> --branch=main

# List Pages projects
wrangler pages project list

# List deployments
wrangler pages deployment list --project-name=<project-name>

# Tail logs from a Pages deployment
wrangler pages deployment tail --project-name=<project-name>
```

### Pages + Next.js

```bash
# Next.js on Cloudflare Pages uses @cloudflare/next-on-pages
npm install @cloudflare/next-on-pages

# Build for Cloudflare
npx @cloudflare/next-on-pages

# Deploy the output
wrangler pages deploy .vercel/output/static --project-name=<project-name>
```

### Pages Environment Variables

```bash
# Set environment variable for production
wrangler pages secret put <VAR_NAME> --project-name=<project-name>
# Prompts for value interactively

# Or via API (non-interactive)
curl -X PATCH "https://api.cloudflare.com/client/v4/accounts/<account-id>/pages/projects/<project-name>" \
  -H "Authorization: Bearer <api-token>" \
  -H "Content-Type: application/json" \
  -d '{
    "deployment_configs": {
      "production": {
        "env_vars": {
          "DATABASE_URL": { "value": "your-connection-string" }
        }
      }
    }
  }'
```

## Workers (Serverless Functions)

```bash
# Scaffold a new Worker
wrangler init <worker-name>

# Dev server (local)
wrangler dev

# Deploy Worker
wrangler deploy

# Tail Worker logs (live)
wrangler tail

# List Workers
wrangler deployments list

# Set secrets
wrangler secret put <SECRET_NAME>
# Prompts for value

# List secrets
wrangler secret list

# Delete a Worker
wrangler delete
```

### wrangler.toml Configuration

```toml
name = "my-worker"
main = "src/index.ts"
compatibility_date = "2024-01-01"

# Bind a D1 database
[[d1_databases]]
binding = "DB"
database_name = "my-database"
database_id = "<database-id>"

# Bind R2 bucket
[[r2_buckets]]
binding = "BUCKET"
bucket_name = "my-bucket"

# Bind KV namespace
[[kv_namespaces]]
binding = "KV"
id = "<namespace-id>"

# Environment-specific config
[env.production]
vars = { ENVIRONMENT = "production" }

[env.staging]
vars = { ENVIRONMENT = "staging" }
```

## D1 (Edge SQLite Database)

```bash
# Create a D1 database
wrangler d1 create <database-name>
# Output: database_id (add to wrangler.toml)

# List databases
wrangler d1 list

# Execute SQL
wrangler d1 execute <database-name> --command="SELECT * FROM users LIMIT 10"

# Execute SQL from file
wrangler d1 execute <database-name> --file=./schema.sql

# Execute against remote (production) database
wrangler d1 execute <database-name> --remote --command="SELECT COUNT(*) FROM users"

# Run migrations
wrangler d1 migrations create <database-name> <migration-name>
# Creates: migrations/0001_<name>.sql

wrangler d1 migrations apply <database-name>        # local
wrangler d1 migrations apply <database-name> --remote  # production
```

## R2 (Object Storage)

```bash
# Create a bucket
wrangler r2 bucket create <bucket-name>

# List buckets
wrangler r2 bucket list

# Upload a file
wrangler r2 object put <bucket-name>/<key> --file=<local-path>

# Download a file
wrangler r2 object get <bucket-name>/<key>

# Delete a file
wrangler r2 object delete <bucket-name>/<key>
```

### R2 Public Access

```bash
# Enable public access via custom domain
# 🚧 HUMAN GATE — Must enable via Cloudflare dashboard:
# R2 > bucket > Settings > Public Access > Custom Domain
# Or use a Worker to serve R2 objects publicly with access control
```

## KV (Key-Value Storage)

```bash
# Create a KV namespace
wrangler kv namespace create <NAMESPACE>
# Output: id (add to wrangler.toml)

# Create preview namespace (for dev)
wrangler kv namespace create <NAMESPACE> --preview

# List namespaces
wrangler kv namespace list

# Write a key
wrangler kv key put --namespace-id=<id> <key> <value>

# Read a key
wrangler kv key get --namespace-id=<id> <key>

# List keys
wrangler kv key list --namespace-id=<id>

# Delete a key
wrangler kv key delete --namespace-id=<id> <key>

# Bulk write from JSON
wrangler kv bulk put --namespace-id=<id> data.json
```

## DNS Management

```bash
# List zones (domains)
curl -s "https://api.cloudflare.com/client/v4/zones" \
  -H "Authorization: Bearer <api-token>" | jq '.result[] | {id, name}'

# Add DNS record
curl -X POST "https://api.cloudflare.com/client/v4/zones/<zone-id>/dns_records" \
  -H "Authorization: Bearer <api-token>" \
  -H "Content-Type: application/json" \
  -d '{
    "type": "CNAME",
    "name": "app",
    "content": "<project-name>.pages.dev",
    "proxied": true
  }'

# List DNS records
curl -s "https://api.cloudflare.com/client/v4/zones/<zone-id>/dns_records" \
  -H "Authorization: Bearer <api-token>" | jq '.result[] | {id, type, name, content}'

# Delete DNS record
curl -X DELETE "https://api.cloudflare.com/client/v4/zones/<zone-id>/dns_records/<record-id>" \
  -H "Authorization: Bearer <api-token>"
```

**🚧 HUMAN GATE:** Adding a domain to Cloudflare requires changing nameservers at the registrar to Cloudflare's nameservers. This is a registrar-side action.

## Common Patterns

### Worker as API Gateway

```typescript
// src/index.ts — Worker that routes to different backends
export default {
  async fetch(request: Request, env: Env) {
    const url = new URL(request.url);

    if (url.pathname.startsWith('/api/')) {
      // Forward to your backend
      return fetch(`https://your-backend.railway.app${url.pathname}`, request);
    }

    // Serve static from R2 or return from KV cache
    const cached = await env.KV.get(url.pathname);
    if (cached) return new Response(cached);

    return new Response('Not Found', { status: 404 });
  }
};
```

### D1 + Drizzle ORM

```typescript
// Drizzle works with D1 — common pattern for typed database access
import { drizzle } from 'drizzle-orm/d1';
import * as schema from './schema';

export default {
  async fetch(request: Request, env: Env) {
    const db = drizzle(env.DB, { schema });
    const users = await db.select().from(schema.users).all();
    return Response.json(users);
  }
};
```

## Dependency Position

- **Depends on:** Nothing for core setup. DNS zone must exist for domain features.
- **Depended on by:** Apps using Workers/Pages for hosting, R2 for storage.
- **Layer 1 candidate:** Create D1/R2/KV resources early (they're independent).
- **Layer 2 candidate:** Deploy to Pages for the URL.
- **Layer 3:** Wire DNS, custom domains, webhook Workers.

## Failure Modes

| Error | Cause | Fix |
|---|---|---|
| `wrangler: command not found` | Wrangler not installed | `npm install -g wrangler` |
| `Authentication error` | Token expired or wrong scope | Re-run `wrangler login` or check API token permissions |
| `D1_ERROR: no such table` | Migrations not applied | `wrangler d1 migrations apply <db> --remote` |
| `R2 object not found` | Wrong key or bucket | Check bucket name and key path |
| `Pages build failed` | Incompatible framework output | Check `@cloudflare/next-on-pages` compatibility |
| `Worker size limit exceeded` | Worker bundle > 1MB (free) / 10MB (paid) | Reduce dependencies or use R2 for large assets |
| `DNS CNAME flattening` | CNAME on apex domain | Cloudflare handles this automatically (CNAME flattening) |
