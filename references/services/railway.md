# Service Reference: Railway

Railway provides infrastructure hosting (apps, databases, cron jobs) with zero-config deployments from Git repos.

## CLI Installation & Auth

```bash
# Install Railway CLI
npm install -g @railway/cli

# Authenticate (opens browser)
railway login

# Or non-interactive with token
railway login --token <token>
```

**Getting a token:** Create at railway.com/account/tokens.

## Project Management

```bash
# Create new project
railway init
# Interactive: prompts for project name, creates project

# Link current directory to existing project
railway link

# List projects
railway list

# Open project dashboard in browser
railway open
```

## Deployment

```bash
# Deploy current directory
railway up
# Deploys from current directory, auto-detects framework

# Deploy from Git (preferred for production)
# Connect a GitHub repo in the Railway dashboard
# Railway auto-deploys on push

# Get deployment status
railway status

# View logs
railway logs
```

## Environment Variables

```bash
# Set variable
railway variables set KEY=value

# Set multiple
railway variables set STRIPE_SECRET_KEY=sk_test_... DATABASE_URL=postgresql://...

# List variables
railway variables list

# Get specific variable
railway variables get DATABASE_URL
```

## Database Services

Railway can provision databases directly:

```bash
# Add PostgreSQL to your project
railway add --database postgres

# Add Redis
railway add --database redis

# Get database connection string
railway variables get DATABASE_URL
```

## Domain Configuration

```bash
# Generate a Railway domain (*.up.railway.app)
railway domain

# Add custom domain
railway domain --set yourdomain.com
# Follow the DNS instructions in output
```

**🚧 HUMAN GATE:** Custom domain DNS records must be configured at your registrar.

## Wiring with Other Services

Railway sets DATABASE_URL automatically when you add a database. For external services:

```bash
# Stripe
railway variables set STRIPE_SECRET_KEY=sk_test_...
railway variables set STRIPE_WEBHOOK_SECRET=whsec_...
railway variables set NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY=pk_test_...

# Supabase (if using external DB)
railway variables set NEXT_PUBLIC_SUPABASE_URL=https://xxx.supabase.co
railway variables set SUPABASE_SERVICE_ROLE_KEY=eyJ...

# App URL (for webhooks and redirects)
railway variables set NEXT_PUBLIC_APP_URL=https://your-app.up.railway.app
```

## Railway vs Vercel

| Feature | Railway | Vercel |
|---|---|---|
| Frontend hosting | Yes | Yes (optimized for Next.js) |
| Backend/API | Yes (any language) | Serverless functions only |
| Databases | Built-in Postgres, Redis, MySQL | Via integrations |
| Docker support | Yes | Limited |
| Pricing model | Usage-based ($5/mo + resources) | Per-seat + usage |
| Best for | Full-stack with backend services | Next.js/frontend-focused |

Use Railway when you need persistent backend processes, Docker containers, or built-in databases.
Use Vercel when you're building primarily with Next.js and want zero-config frontend deployment.

## Failure Modes

| Error | Cause | Fix |
|---|---|---|
| `No railway project found` | Not linked | `railway link` or `railway init` |
| Build fails | Missing dependencies or wrong build command | Check Nixpacks auto-detection or set custom build command |
| 502 Bad Gateway | App crashed on start | `railway logs` — check for missing env vars |
| Custom domain not resolving | DNS not propagated | Wait, check with `dig yourdomain.com` |
