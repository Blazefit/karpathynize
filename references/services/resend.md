# Service Reference: Resend

Resend provides transactional email delivery with a developer-friendly API.

## Setup

```bash
# Install SDK (no standalone CLI)
npm install resend
```

**🚧 HUMAN GATE:** Create account and get API key at resend.com/api-keys. Resend does not have a CLI for account management. This is a one-time browser operation.

Add to `.env.local`:
```env
RESEND_API_KEY=re_...
```

## Domain Verification

To send emails from your custom domain (not `onboarding@resend.dev`):

**🚧 HUMAN GATE:** Domain verification requires adding DNS records. Do this at resend.com/domains → Add Domain. Resend provides the required DNS records (MX, TXT/SPF, DKIM).

Verify via API:
```bash
# Check domain verification status
curl -X GET "https://api.resend.com/domains" \
  -H "Authorization: Bearer re_..." \
  -H "Content-Type: application/json"

# Verify a specific domain
curl -X POST "https://api.resend.com/domains/<domain-id>/verify" \
  -H "Authorization: Bearer re_..."
```

## Sending Emails (API)

```bash
# Send a test email via curl
curl -X POST "https://api.resend.com/emails" \
  -H "Authorization: Bearer re_..." \
  -H "Content-Type: application/json" \
  -d '{
    "from": "hello@yourdomain.com",
    "to": "test@example.com",
    "subject": "Test Email",
    "html": "<p>Hello from your app!</p>"
  }'
```

## App Integration Pattern

```typescript
// lib/resend.ts
import { Resend } from 'resend';

export const resend = new Resend(process.env.RESEND_API_KEY);

// Usage in API route or server action
await resend.emails.send({
  from: 'Your App <hello@yourdomain.com>',
  to: user.email,
  subject: 'Welcome!',
  html: '<p>Welcome to the app.</p>'
});
```

## Wiring with Vercel

```bash
# Add API key to Vercel
vercel env add RESEND_API_KEY production <<< "re_..."
```

No webhook configuration needed — Resend is fire-and-forget for basic transactional email. For delivery tracking, configure webhook at resend.com/webhooks (optional).

## Failure Modes

| Error | Cause | Fix |
|---|---|---|
| 403 `domain not verified` | Sending from unverified domain | Complete DNS verification |
| Emails in spam | Missing SPF/DKIM records | Add all DNS records Resend provides |
| 401 `invalid api key` | Wrong or expired API key | Check `RESEND_API_KEY` value |
