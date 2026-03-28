# Service Reference: Linear

Linear provides issue tracking, project management, cycles (sprints), and a powerful API with webhooks. It's developer-focused and has first-class API support for everything — almost nothing requires the browser.

## API Authentication

Linear doesn't have a traditional CLI. All automation goes through the GraphQL API or OAuth.

```bash
# Personal API key (for scripts and agents)
# Create at linear.app/settings/api

# Test your API key
curl -s https://api.linear.app/graphql \
  -H "Authorization: <api-key>" \
  -H "Content-Type: application/json" \
  -d '{"query": "{ viewer { id name email } }"}' | jq
```

**Getting an API key:** Go to linear.app/settings/api > "Personal API keys" > Create key. This key has the same permissions as your Linear account.

### OAuth App Setup (for multi-user apps)

**🚧 HUMAN GATE:** Create OAuth apps at linear.app/settings/api > "OAuth applications" > Create.

**Required fields:**
- **Application name:** Your app's name
- **Redirect URIs:** `https://your-app.com/api/auth/callback/linear`
- **Webhook URL** (optional): `https://your-app.com/api/webhooks/linear`

**Output:** Client ID and Client Secret.

```typescript
// OAuth flow
// 1. Redirect to:
// https://linear.app/oauth/authorize?
//   client_id=<CLIENT_ID>&
//   redirect_uri=<CALLBACK>&
//   response_type=code&
//   scope=read,write,issues:create&
//   state=<csrf-token>&
//   actor=application

// 2. Exchange code for token
const response = await fetch('https://api.linear.app/oauth/token', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({
    grant_type: 'authorization_code',
    client_id: process.env.LINEAR_CLIENT_ID,
    client_secret: process.env.LINEAR_CLIENT_SECRET,
    redirect_uri: process.env.LINEAR_REDIRECT_URI,
    code: code,
  }),
});
const { access_token } = await response.json();
```

## GraphQL API

Linear uses GraphQL exclusively (no REST API). Base URL: `https://api.linear.app/graphql`

### Teams & Workspace

```bash
# List teams
curl -s https://api.linear.app/graphql \
  -H "Authorization: <api-key>" \
  -H "Content-Type: application/json" \
  -d '{"query": "{ teams { nodes { id name key } } }"}' | jq

# Get workspace info
curl -s https://api.linear.app/graphql \
  -H "Authorization: <api-key>" \
  -H "Content-Type: application/json" \
  -d '{"query": "{ organization { id name urlKey } }"}' | jq
```

### Issues

```bash
# Create an issue
curl -s https://api.linear.app/graphql \
  -H "Authorization: <api-key>" \
  -H "Content-Type: application/json" \
  -d '{
    "query": "mutation($input: IssueCreateInput!) { issueCreate(input: $input) { success issue { id identifier url } } }",
    "variables": {
      "input": {
        "teamId": "<team-id>",
        "title": "Implement webhook handler",
        "description": "Add Stripe webhook handling for subscription events",
        "priority": 2,
        "labelIds": ["<label-id>"]
      }
    }
  }' | jq

# List issues (with filtering)
curl -s https://api.linear.app/graphql \
  -H "Authorization: <api-key>" \
  -H "Content-Type: application/json" \
  -d '{
    "query": "{ issues(filter: { team: { key: { eq: \"ENG\" } }, state: { type: { in: [\"started\", \"unstarted\"] } } }, first: 20) { nodes { id identifier title state { name } assignee { name } priority } } }"
  }' | jq

# Update an issue
curl -s https://api.linear.app/graphql \
  -H "Authorization: <api-key>" \
  -H "Content-Type: application/json" \
  -d '{
    "query": "mutation($id: String!, $input: IssueUpdateInput!) { issueUpdate(id: $id, input: $input) { success } }",
    "variables": {
      "id": "<issue-id>",
      "input": {
        "stateId": "<done-state-id>",
        "assigneeId": "<user-id>"
      }
    }
  }' | jq

# Search issues
curl -s https://api.linear.app/graphql \
  -H "Authorization: <api-key>" \
  -H "Content-Type: application/json" \
  -d '{"query": "{ searchIssues(term: \"webhook\", first: 10) { nodes { id identifier title } } }"}' | jq
```

### Labels

```bash
# List labels
curl -s https://api.linear.app/graphql \
  -H "Authorization: <api-key>" \
  -H "Content-Type: application/json" \
  -d '{"query": "{ issueLabels(first: 50) { nodes { id name color } } }"}' | jq

# Create a label
curl -s https://api.linear.app/graphql \
  -H "Authorization: <api-key>" \
  -H "Content-Type: application/json" \
  -d '{
    "query": "mutation($input: IssueLabelCreateInput!) { issueLabelCreate(input: $input) { success issueLabel { id name } } }",
    "variables": {
      "input": {
        "teamId": "<team-id>",
        "name": "deployment",
        "color": "#0366d6"
      }
    }
  }' | jq
```

### Projects

```bash
# List projects
curl -s https://api.linear.app/graphql \
  -H "Authorization: <api-key>" \
  -H "Content-Type: application/json" \
  -d '{"query": "{ projects(first: 20) { nodes { id name state progress } } }"}' | jq

# Create a project
curl -s https://api.linear.app/graphql \
  -H "Authorization: <api-key>" \
  -H "Content-Type: application/json" \
  -d '{
    "query": "mutation($input: ProjectCreateInput!) { projectCreate(input: $input) { success project { id name url } } }",
    "variables": {
      "input": {
        "name": "Q1 Launch",
        "teamIds": ["<team-id>"],
        "description": "Ship v1.0 by end of Q1"
      }
    }
  }' | jq
```

## Webhooks

```bash
# Create a webhook
curl -s https://api.linear.app/graphql \
  -H "Authorization: <api-key>" \
  -H "Content-Type: application/json" \
  -d '{
    "query": "mutation($input: WebhookCreateInput!) { webhookCreate(input: $input) { success webhook { id enabled } } }",
    "variables": {
      "input": {
        "url": "https://your-app.com/api/webhooks/linear",
        "teamId": "<team-id>",
        "resourceTypes": ["Issue", "Comment", "Project"],
        "secret": "<webhook-secret>",
        "enabled": true
      }
    }
  }' | jq

# List webhooks
curl -s https://api.linear.app/graphql \
  -H "Authorization: <api-key>" \
  -H "Content-Type: application/json" \
  -d '{"query": "{ webhooks { nodes { id url enabled resourceTypes } } }"}' | jq

# Delete a webhook
curl -s https://api.linear.app/graphql \
  -H "Authorization: <api-key>" \
  -H "Content-Type: application/json" \
  -d '{
    "query": "mutation($id: String!) { webhookDelete(id: $id) { success } }",
    "variables": { "id": "<webhook-id>" }
  }' | jq
```

### Webhook Payload Structure

```typescript
// Linear webhook handler
export async function POST(request: Request) {
  const body = await request.json();
  const signature = request.headers.get('linear-signature');

  // Verify signature (HMAC-SHA256)
  const hmac = crypto.createHmac('sha256', process.env.LINEAR_WEBHOOK_SECRET!);
  hmac.update(JSON.stringify(body));
  const expectedSignature = hmac.digest('hex');

  if (signature !== expectedSignature) {
    return new Response('Invalid signature', { status: 401 });
  }

  // body.action: "create" | "update" | "remove"
  // body.type: "Issue" | "Comment" | "Project" | etc.
  // body.data: the full object
  // body.updatedFrom: previous values (on update)

  switch (body.type) {
    case 'Issue':
      if (body.action === 'update' && body.data.state?.name === 'Done') {
        // Issue was marked done — trigger deployment, notify, etc.
      }
      break;
  }

  return new Response('OK', { status: 200 });
}
```

### Common Webhook Use Cases

| Resource | Event | Use Case |
|---|---|---|
| `Issue` | create | Auto-create branch, notify Slack |
| `Issue` | update (state → Done) | Trigger deployment, close PR |
| `Comment` | create | Sync to Slack thread |
| `Project` | update (progress) | Update dashboard/status page |

## Linear SDK (TypeScript)

```typescript
// npm install @linear/sdk
import { LinearClient } from '@linear/sdk';

const linear = new LinearClient({ apiKey: process.env.LINEAR_API_KEY! });

// Create issue
const issue = await linear.createIssue({
  teamId: '<team-id>',
  title: 'Deploy webhook handler',
  priority: 2,
});

// List my assigned issues
const me = await linear.viewer;
const myIssues = await me.assignedIssues({
  filter: { state: { type: { in: ['started', 'unstarted'] } } },
});
```

## Required Environment Variables

```bash
# For API access
LINEAR_API_KEY=           # Personal API key

# For OAuth apps
LINEAR_CLIENT_ID=
LINEAR_CLIENT_SECRET=
LINEAR_REDIRECT_URI=

# For webhooks
LINEAR_WEBHOOK_SECRET=    # shared secret for signature verification
```

## Dependency Position

- **Depends on:** Deployment URL (for webhooks). Nothing for API access.
- **Depended on by:** DevOps workflows, project sync tools, status dashboards.
- **Layer 1:** Create API key, set up labels and project structure.
- **Layer 2:** Deploy app (needed for webhook URL).
- **Layer 3:** Wire webhooks to deployment URL.
- **Integration note:** Linear webhooks are team-scoped, not org-scoped. Create one per team you want to track.

## Failure Modes

| Error | Cause | Fix |
|---|---|---|
| `Authentication required` | Missing or invalid API key | Check `LINEAR_API_KEY` is set and valid |
| `Forbidden` | API key lacks permission for this resource | Use a key from an account with appropriate access |
| `Variable "$input" got invalid value` | Malformed GraphQL variables | Check field names match Linear's schema |
| Webhook not firing | Wrong team ID or resource types | Verify webhook config with list query |
| Webhook 401 | Signature mismatch | Ensure `LINEAR_WEBHOOK_SECRET` matches webhook config |
| `Entity not found` | Wrong ID format (Linear uses UUIDs) | Use the `id` field from queries, not `identifier` (ENG-123) |
| Rate limit (1500 req/hr) | Too many API calls | Batch operations, use pagination, cache responses |
