# Service Reference: Vercel

Vercel provides hosting, serverless functions, edge middleware, and domain management for Next.js apps.

## CLI Authentication

```bash
# Login (opens browser)
vercel login

# Login with token (non-interactive, for agents)
vercel login --token <vercel-token>
# Or set: export VERCEL_TOKEN=<token>
```

**Getting a token:** Create at vercel.com/account/tokens. Enables fully non-interactive CLI usage.

## Project Deployment

```bash
# Deploy current directory (interactive first time — creates project)
vercel

# Non-interactive deploy (uses defaults)
vercel --yes

# Deploy to production
vercel --prod --yes

# Deploy with specific env vars
vercel --prod --yes --env NEXT_PUBLIC_APP_URL=https://myapp.com

# Get deployment URL from output
# Output line: "https://my-app-abc123.vercel.app"
```

## Environment Variables

```bash
# Add env var (interactive)
vercel env add <VAR_NAME>

# Add env var non-interactively
echo "<value>" | vercel env add <VAR_NAME> production
# Or with heredoc:
vercel env add <VAR_NAME> production <<< "<value>"

# Add to multiple environments
vercel env add <VAR_NAME> production preview development <<< "<value>"

# List all env vars
vercel env ls

# Remove env var
vercel env rm <VAR_NAME> production

# Pull env vars to .env.local
vercel env pull .env.local

# Force overwrite existing env var
echo "<new-value>" | vercel env add <VAR_NAME> production --force
```

## Domain Management

```bash
# Add custom domain
vercel domains add <domain>
# Output: DNS records needed (A record or CNAME)

# List domains
vercel domains ls

# Inspect domain status (DNS propagation check)
vercel domains inspect <domain>

# Remove domain
vercel domains rm <domain>

# Verify domain
vercel domains verify <domain>
```

**🚧 HUMAN GATE:** DNS records must be added at the domain registrar. Vercel CLI tells you what records to add, but can't add them for you.

Typical DNS records for Vercel:
- **A record:** `76.76.21.21` (for apex domain, e.g., `yourapp.com`)
- **CNAME:** `cname.vercel-dns.com` (for subdomains, e.g., `www.yourapp.com`)

## Project Management

```bash
# Link current directory to existing Vercel project
vercel link

# Inspect deployment
vercel inspect <deployment-url>

# List deployments
vercel ls

# List projects
vercel project ls

# Remove deployment
vercel rm <deployment-url>

# Promote a preview deployment to production
vercel promote <deployment-url>
```

## Secrets & Configuration

```bash
# Vercel secrets (team-level, shared across projects)
vercel secrets add <name> <value>
vercel secrets ls
vercel secrets rm <name>
```

## Vercel.json Configuration

For non-default routing, headers, redirects:

```json
{
  "rewrites": [
    { "source": "/api/:path*", "destination": "/api/:path*" }
  ],
  "headers": [
    {
      "source": "/api/(.*)",
      "headers": [
        { "key": "Access-Control-Allow-Origin", "value": "*" }
      ]
    }
  ],
  "redirects": [
    { "source": "/old-path", "destination": "/new-path", "permanent": true }
  ]
}
```

## Auto-Set Environment Variables

Vercel automatically sets these (no manual config needed):
- `VERCEL` — Always `1` on Vercel
- `VERCEL_URL` — The deployment URL (without `https://`)
- `VERCEL_ENV` — `production`, `preview`, or `development`
- `VERCEL_GIT_COMMIT_SHA` — Git commit hash

Useful for constructing the app URL dynamically:
```typescript
const appUrl = process.env.NEXT_PUBLIC_APP_URL ||
  (process.env.VERCEL_URL ? `https://${process.env.VERCEL_URL}` : 'http://localhost:3000');
```

## Failure Modes

| Error | Cause | Fix |
|---|---|---|
| 404 on API routes | API routes not in correct directory | Ensure `app/api/` or `pages/api/` structure |
| Build fails | Missing env vars during build | Set vars for the correct environment |
| Domain not resolving | DNS not propagated | Wait 5-60 min, check with `vercel domains inspect` |
| 500 on serverless function | Runtime error or missing env var | Check function logs with `vercel logs <url>` |
| `vercel env add` hangs | Waiting for stdin | Pipe value: `echo "val" | vercel env add NAME production` |
