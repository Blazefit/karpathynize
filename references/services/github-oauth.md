# Service Reference: GitHub (OAuth & API)

GitHub provides OAuth authentication, repository management, webhooks, GitHub Actions CI/CD, and a comprehensive REST/GraphQL API. This reference focuses on OAuth app setup (for "Sign in with GitHub") and API automation via the `gh` CLI.

## CLI Authentication

```bash
# Install GitHub CLI (if needed)
brew install gh        # macOS
# or: sudo apt install gh   # Linux

# Login (interactive — opens browser)
gh auth login

# Login with token (non-interactive, for agents)
gh auth login --with-token <<< "<personal-access-token>"

# Check auth status
gh auth status

# Get current token (for use in scripts)
gh auth token
```

**Getting a PAT:** Create at github.com/settings/tokens. Use "Fine-grained tokens" for scoped access (recommended) or "Classic tokens" for broader access.

## OAuth App Setup

GitHub OAuth lets users "Sign in with GitHub" in your app. There are two types:
- **OAuth Apps** — simpler, broader scope, good for most apps
- **GitHub Apps** — more granular permissions, better for integrations

### Creating an OAuth App

**🚧 HUMAN GATE:** OAuth Apps must be created in the browser at github.com/settings/applications/new (or org settings for org-owned apps).

**Required fields:**
- **Application name:** Your app's name
- **Homepage URL:** `https://your-app.com`
- **Authorization callback URL:** `https://your-app.com/api/auth/callback/github`
  - For Supabase Auth: `https://<project-ref>.supabase.co/auth/v1/callback`
  - For Clerk: `https://clerk.<your-domain>/v1/oauth_callback`
  - For NextAuth: `https://your-app.com/api/auth/callback/github`
  - For local dev: `http://localhost:3000/api/auth/callback/github`

**Output:** Client ID and Client Secret — these go into your auth provider's config.

### OAuth Flow (for reference in app code)

```typescript
// 1. Redirect user to GitHub authorization
// GET https://github.com/login/oauth/authorize?
//   client_id=<CLIENT_ID>&
//   redirect_uri=<CALLBACK_URL>&
//   scope=read:user,user:email&
//   state=<random-csrf-token>

// 2. GitHub redirects back with a code
// GET <CALLBACK_URL>?code=<code>&state=<state>

// 3. Exchange code for access token
const response = await fetch('https://github.com/login/oauth/access_token', {
  method: 'POST',
  headers: {
    'Accept': 'application/json',
    'Content-Type': 'application/json',
  },
  body: JSON.stringify({
    client_id: process.env.GITHUB_CLIENT_ID,
    client_secret: process.env.GITHUB_CLIENT_SECRET,
    code: code,
  }),
});
const { access_token } = await response.json();

// 4. Use token to get user info
const user = await fetch('https://api.github.com/user', {
  headers: { Authorization: `Bearer ${access_token}` },
}).then(r => r.json());
```

### OAuth Scopes (Common)

| Scope | Grants |
|---|---|
| `read:user` | Read user profile |
| `user:email` | Read user email addresses |
| `repo` | Full access to repositories |
| `read:org` | Read org membership |
| `write:repo_hook` | Manage repo webhooks |

For "Sign in with GitHub" you typically need only `read:user` and `user:email`.

## Wiring GitHub OAuth to Auth Providers

### With Supabase

```bash
# After creating OAuth App and getting Client ID + Secret:
curl -X PATCH "https://api.supabase.com/v1/projects/<ref>/config/auth" \
  -H "Authorization: Bearer <supabase-access-token>" \
  -H "Content-Type: application/json" \
  -d '{
    "external_github_enabled": true,
    "external_github_client_id": "<github-client-id>",
    "external_github_secret": "<github-client-secret>"
  }'
```

### With Clerk

```bash
# 🚧 HUMAN GATE — Configure at clerk.com > your app > Social Connections > GitHub
# Enter the Client ID and Client Secret from your GitHub OAuth App
# Clerk handles the callback URL automatically
```

### With NextAuth.js

```typescript
// app/api/auth/[...nextauth]/route.ts
import NextAuth from 'next-auth';
import GitHubProvider from 'next-auth/providers/github';

const handler = NextAuth({
  providers: [
    GitHubProvider({
      clientId: process.env.GITHUB_CLIENT_ID!,
      clientSecret: process.env.GITHUB_CLIENT_SECRET!,
    }),
  ],
});

export { handler as GET, handler as POST };
```

## Repository Webhooks

```bash
# Create a webhook on a repo
gh api repos/<owner>/<repo>/hooks \
  --method POST \
  -f name=web \
  -f "config[url]=https://your-app.com/api/webhooks/github" \
  -f "config[content_type]=json" \
  -f "config[secret]=<webhook-secret>" \
  -f "events[]=push" \
  -f "events[]=pull_request" \
  -f active=true

# List webhooks
gh api repos/<owner>/<repo>/hooks

# Delete a webhook
gh api repos/<owner>/<repo>/hooks/<hook-id> --method DELETE

# Test a webhook (redeliver most recent)
gh api repos/<owner>/<repo>/hooks/<hook-id>/tests --method POST
```

### Common Webhook Events

| Event | Trigger |
|---|---|
| `push` | Code pushed to any branch |
| `pull_request` | PR opened, closed, merged, updated |
| `issues` | Issue opened, closed, commented |
| `release` | New release published |
| `workflow_run` | GitHub Actions workflow completed |

## GitHub API via CLI

```bash
# Get authenticated user
gh api user

# Create a repository
gh repo create <name> --public --description="My app"

# List repositories
gh repo list --limit=20

# Create an issue
gh issue create --repo=<owner>/<repo> --title="Bug" --body="Description"

# Create a release
gh release create v1.0.0 --title="v1.0.0" --notes="First release"

# GraphQL query
gh api graphql -f query='
  query {
    viewer {
      login
      repositories(first: 5, orderBy: {field: UPDATED_AT, direction: DESC}) {
        nodes { name, url }
      }
    }
  }'
```

## Required Environment Variables

```bash
# For OAuth (app code)
GITHUB_CLIENT_ID=
GITHUB_CLIENT_SECRET=

# For API access (server-side)
GITHUB_TOKEN=         # PAT or app installation token

# For webhooks
GITHUB_WEBHOOK_SECRET=  # shared secret for signature verification
```

## Dependency Position

- **Depends on:** Nothing for API access. Deployment URL for webhook endpoints and OAuth callback.
- **Depended on by:** Auth providers (Supabase, Clerk, NextAuth) for "Sign in with GitHub."
- **Layer 1:** Create OAuth App (human gate), get credentials.
- **Layer 2:** Deploy app to get callback URL.
- **Layer 3:** Wire OAuth credentials into auth provider, set up webhooks pointing to deployment URL.

## Failure Modes

| Error | Cause | Fix |
|---|---|---|
| `redirect_uri_mismatch` | Callback URL doesn't match OAuth App config | Update callback URL in GitHub OAuth App settings |
| `bad_verification_code` | OAuth code expired (10 min lifetime) or already used | Codes are single-use — restart the flow |
| `401 Bad credentials` | Token expired or revoked | Re-authenticate: `gh auth login` or regenerate PAT |
| `403 rate limit exceeded` | Hit API rate limit (5000/hr authenticated, 60/hr unauth) | Wait for reset or use conditional requests (ETags) |
| `Webhook 422 Validation failed` | Invalid webhook URL or events | Check URL is HTTPS and events are valid |
| `Webhook signature mismatch` | Wrong `GITHUB_WEBHOOK_SECRET` | Ensure secret matches between app and webhook config |
