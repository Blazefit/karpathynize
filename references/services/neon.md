# Service Reference: Neon

Neon provides serverless PostgreSQL with instant branching, autoscaling to zero, and a generous free tier.

## CLI Installation & Auth

```bash
# Install neonctl
brew install neonctl
# Or via npm:
npm install -g neonctl

# Authenticate (opens browser)
neonctl auth

# Or non-interactive with API key
export NEON_API_KEY=<your-api-key>
```

**Getting an API key:** Create at console.neon.tech/app/settings/api-keys. Enables fully non-interactive CLI usage.

## Project Management

```bash
# List projects
neonctl projects list

# Create project
neonctl projects create --name my-saas-app --region-id aws-us-east-1
# Output includes: project ID, connection string, branch ID

# Set default project context (avoids --project-id on every command)
neonctl set-context --project-id <project-id>

# Get connection string
neonctl connection-string --project-id <project-id>
# Output: postgresql://neondb_owner:***@ep-xxx.us-east-1.aws.neon.tech/neondb?sslmode=require
```

## Branch Management (Neon's killer feature)

```bash
# List branches
neonctl branches list --project-id <project-id>

# Create dev branch from main
neonctl branches create --name dev --project-id <project-id>

# Create preview branch (e.g., per PR)
neonctl branches create --name preview/pr-42 \
  --project-id <project-id> \
  --expires-at "$(date -u -v+7d +%Y-%m-%dT%H:%M:%SZ)"  # macOS
  # Linux: --expires-at "$(date -u -d '+7 days' +%Y-%m-%dT%H:%M:%SZ)"

# Get connection string for a specific branch
neonctl connection-string --branch dev --project-id <project-id>

# Delete branch
neonctl branches delete <branch-id> --project-id <project-id>

# Reset branch to parent state
neonctl branches reset <branch-id> --project-id <project-id>
```

## SQL Execution (direct from CLI)

```bash
# Run SQL query
neonctl sql "SELECT version();" --project-id <project-id>

# Run SQL from file (migrations)
neonctl sql --file schema.sql --project-id <project-id>

# Run against specific branch
neonctl sql "SELECT * FROM users LIMIT 5;" \
  --branch dev --project-id <project-id>
```

## Environment Variables

```env
DATABASE_URL=postgresql://neondb_owner:<password>@ep-xxx.us-east-1.aws.neon.tech/neondb?sslmode=require
# For connection pooling (recommended for serverless):
DATABASE_URL_POOLED=postgresql://neondb_owner:<password>@ep-xxx.us-east-1.aws.neon.tech/neondb?sslmode=require&pgbouncer=true
```

## Wiring with Vercel

```bash
vercel env add DATABASE_URL production <<< "postgresql://..."
vercel env add DATABASE_URL preview <<< "postgresql://...branch-url..."
```

For per-preview-deployment branches, use the Neon Vercel Integration:
**🚧 HUMAN GATE:** Install at vercel.com/integrations/neon — creates a branch per Vercel preview deploy automatically.

## Wiring with ORMs

Neon works with any PostgreSQL ORM. Common patterns:

```bash
# Drizzle ORM
npm install drizzle-orm @neondatabase/serverless
npm install -D drizzle-kit

# Prisma
npm install prisma @prisma/client
npx prisma init
# Set DATABASE_URL in .env, then:
npx prisma db push
```

## Failure Modes

| Error | Cause | Fix |
|---|---|---|
| `connection refused` | Compute endpoint suspended (scale to zero) | First request wakes it — retry after ~200ms |
| `password authentication failed` | Wrong connection string or branch credentials | Re-fetch with `neonctl connection-string` |
| `SSL required` | Missing `?sslmode=require` in connection string | Append to DATABASE_URL |
| Branch operations fail | API key expired or wrong project | `neonctl auth` or check `NEON_API_KEY` |
| `too many connections` | Not using connection pooling | Add `&pgbouncer=true` to connection string |
