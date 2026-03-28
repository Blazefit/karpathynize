# Service Reference: Supabase

Supabase provides auth, PostgreSQL database, realtime subscriptions, edge functions, and storage.

## CLI Authentication

```bash
# Login (opens browser)
supabase login

# Login with access token (non-interactive, for agents)
supabase login --token <personal-access-token>
```

**Getting a personal access token (PAT):** 🚧 HUMAN GATE — Must be created at supabase.com/dashboard/account/tokens. The PAT enables fully non-interactive CLI usage.

## Project Management

```bash
# List organizations
supabase orgs list

# Create project
supabase projects create <project-name> \
  --org-id <org-id> \
  --db-password <password> \
  --region us-east-1

# Available regions: us-east-1, us-west-1, eu-west-1, ap-southeast-1, ap-northeast-1, etc.

# List projects
supabase projects list

# Get API keys for a project
supabase projects api-keys --project-ref <ref>

# Link local directory to remote project
supabase link --project-ref <ref>
```

## Database Migrations

```bash
# Initialize local Supabase config
supabase init

# Create new migration
supabase migration new <migration-name>
# Creates: supabase/migrations/<timestamp>_<name>.sql

# Push migrations to remote
supabase db push

# Pull remote schema to local
supabase db pull

# Reset local database
supabase db reset

# Lint database for issues
supabase db lint

# Generate TypeScript types from schema
supabase gen types typescript --project-id <ref> > types/supabase.ts
```

## Auth Configuration

```bash
# Configure auth via config.toml
# Edit supabase/config.toml, then:
supabase config push

# Or via Management API:
curl -X PATCH "https://api.supabase.com/v1/projects/<ref>/config/auth" \
  -H "Authorization: Bearer <access-token>" \
  -H "Content-Type: application/json" \
  -d '{
    "site_url": "https://your-app.com",
    "uri_allow_list": "http://localhost:3000,https://your-app.com",
    "external_email_enabled": true,
    "external_phone_enabled": false
  }'
```

### OAuth Provider Setup

**🚧 HUMAN GATE:** OAuth provider apps (Google, GitHub, etc.) must be created in the provider's developer console. The skill can configure Supabase to USE them once created.

```bash
# After creating OAuth app in provider console, configure in Supabase:
curl -X PATCH "https://api.supabase.com/v1/projects/<ref>/config/auth" \
  -H "Authorization: Bearer <access-token>" \
  -H "Content-Type: application/json" \
  -d '{
    "external_google_enabled": true,
    "external_google_client_id": "<google-client-id>",
    "external_google_secret": "<google-client-secret>"
  }'
```

## Edge Functions

```bash
# Create a new edge function
supabase functions new <function-name>

# Deploy a function
supabase functions deploy <function-name>

# Set function secrets
supabase secrets set STRIPE_SECRET_KEY=sk_test_...

# List secrets
supabase secrets list

# Invoke a function (for testing)
supabase functions invoke <function-name> --body '{"key": "value"}'
```

## Local Development

```bash
# Start local Supabase stack (requires Docker)
supabase start

# Get local credentials
supabase status
# Outputs: API URL, anon key, service_role key, DB URL, Studio URL

# Export as env vars
supabase status -o env > .env.local

# Stop local stack
supabase stop
```

## Common Patterns

### RLS Policy Templates

```sql
-- Authenticated users can read their own rows
create policy "Users read own" on public.<table>
  for select using (auth.uid() = user_id);

-- Authenticated users can insert their own rows
create policy "Users insert own" on public.<table>
  for insert with check (auth.uid() = user_id);

-- Service role can do anything (for webhook handlers)
-- No policy needed — service_role bypasses RLS

-- Public read access
create policy "Public read" on public.<table>
  for select using (true);
```

### Auto-Create Profile on Signup

```sql
create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id, email)
  values (new.id, new.email);
  return new;
end;
$$ language plpgsql security definer;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();
```

## Management API (for advanced automation)

Base URL: `https://api.supabase.com/v1`
Auth: `Authorization: Bearer <personal-access-token>`

```bash
# Create project via API
curl -X POST "https://api.supabase.com/v1/projects" \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "my-project",
    "organization_id": "<org-id>",
    "db_pass": "<password>",
    "region": "us-east-1",
    "plan": "free"
  }'

# Check project health
curl "https://api.supabase.com/v1/projects/<ref>/health" \
  -H "Authorization: Bearer <token>"
# Wait for status: ACTIVE_HEALTHY before proceeding

# Get API keys
curl "https://api.supabase.com/v1/projects/<ref>/api-keys" \
  -H "Authorization: Bearer <token>"
```

## Failure Modes

| Error | Cause | Fix |
|---|---|---|
| `permission denied for schema public` | RLS enabled but no matching policy | Add appropriate policy or use service_role key |
| `JWT expired` | Token older than configured expiry | Check auth token lifetime settings |
| `relation does not exist` | Migration not pushed | Run `supabase db push` |
| `duplicate key value` | Migration already applied | `supabase migration repair --status applied` |
| `project not linked` | Forgot to run `supabase link` | `supabase link --project-ref <ref>` |
