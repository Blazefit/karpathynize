# Service Reference: Stripe

Stripe provides payments, subscriptions, billing portal, and webhook event delivery.

## CLI Authentication

```bash
# Login (opens browser for device auth)
stripe login

# Login with API key (non-interactive)
stripe login --api-key sk_test_...

# Check current configuration
stripe config --list
```

## Products & Prices

```bash
# Create product
stripe products create \
  --name="Pro Plan" \
  --description="Full access to all features" \
  --metadata[tier]=pro

# List products
stripe products list --limit=10

# Create monthly price
stripe prices create \
  --product=prod_... \
  --unit-amount=2900 \
  --currency=usd \
  -d "recurring[interval]=month"

# Create annual price
stripe prices create \
  --product=prod_... \
  --unit-amount=29000 \
  --currency=usd \
  -d "recurring[interval]=year"

# Create a free tier price ($0)
stripe prices create \
  --product=prod_... \
  --unit-amount=0 \
  --currency=usd \
  -d "recurring[interval]=month"

# List prices
stripe prices list --limit=10

# Update product
stripe products update prod_... --name="Enterprise Plan"

# Deactivate price (can't delete, only archive)
stripe prices update price_... --active=false
```

## Webhook Endpoints

```bash
# Create webhook endpoint
stripe webhook_endpoints create \
  --url="https://your-app.com/api/webhooks/stripe" \
  --enabled-events="checkout.session.completed" \
  --enabled-events="customer.subscription.created" \
  --enabled-events="customer.subscription.updated" \
  --enabled-events="customer.subscription.deleted" \
  --enabled-events="product.created" \
  --enabled-events="product.updated" \
  --enabled-events="price.created" \
  --enabled-events="price.updated" \
  --enabled-events="invoice.payment_succeeded" \
  --enabled-events="invoice.payment_failed"
# Output includes: whsec_... (webhook signing secret)

# List webhook endpoints
stripe webhook_endpoints list

# Update webhook endpoint
stripe webhook_endpoints update we_... \
  --url="https://new-domain.com/api/webhooks/stripe"

# Delete webhook endpoint
stripe webhook_endpoints delete we_...
```

### Recommended Events for SaaS

| Event | Why |
|---|---|
| `checkout.session.completed` | User completed checkout — activate subscription |
| `customer.subscription.created` | New subscription started |
| `customer.subscription.updated` | Plan change, renewal, etc. |
| `customer.subscription.deleted` | Subscription cancelled |
| `invoice.payment_succeeded` | Successful recurring payment |
| `invoice.payment_failed` | Failed payment — trigger dunning |
| `product.created` / `product.updated` | Sync product catalog |
| `price.created` / `price.updated` | Sync pricing |

## Local Development

```bash
# Forward webhooks to local dev server
stripe listen --forward-to localhost:3000/api/webhooks/stripe
# Outputs a LOCAL webhook signing secret (whsec_...)
# Use this in .env.local — it's different from the production webhook secret

# Trigger test events
stripe trigger checkout.session.completed
stripe trigger customer.subscription.created
stripe trigger invoice.payment_failed

# Tail event logs
stripe events list --limit=5
```

## Customer Portal

```bash
# Create portal configuration
stripe billing_portal_configurations create \
  -d "business_profile[headline]=Manage your subscription" \
  -d "features[subscription_cancel][enabled]=true" \
  -d "features[subscription_cancel][mode]=at_period_end" \
  -d "features[subscription_update][enabled]=true" \
  -d "features[subscription_update][default_allowed_updates][0]=price" \
  -d "features[payment_method_update][enabled]=true"

# List portal configurations
stripe billing_portal_configurations list
```

## Checkout Session (API, not CLI — for reference in app code)

```javascript
// Server-side: create checkout session
const session = await stripe.checkout.sessions.create({
  customer: customerId,  // or customer_email for new customers
  line_items: [{ price: 'price_...', quantity: 1 }],
  mode: 'subscription',
  success_url: `${appUrl}/dashboard?checkout=success`,
  cancel_url: `${appUrl}/pricing?checkout=cancelled`,
  metadata: { userId: user.id }
});
```

## Webhook Handler Pattern (for app code reference)

```typescript
// app/api/webhooks/stripe/route.ts
import Stripe from 'stripe';

const stripe = new Stripe(process.env.STRIPE_SECRET_KEY!);
const webhookSecret = process.env.STRIPE_WEBHOOK_SECRET!;

export async function POST(request: Request) {
  const body = await request.text();
  const signature = request.headers.get('stripe-signature')!;

  let event: Stripe.Event;
  try {
    event = stripe.webhooks.constructEvent(body, signature, webhookSecret);
  } catch (err) {
    return new Response('Webhook signature verification failed', { status: 400 });
  }

  switch (event.type) {
    case 'checkout.session.completed':
      // Activate subscription in your database
      break;
    case 'customer.subscription.updated':
      // Sync subscription status
      break;
    case 'customer.subscription.deleted':
      // Deactivate subscription
      break;
  }

  return new Response('OK', { status: 200 });
}
```

## Test vs. Live Mode

- **Test mode:** Uses `pk_test_` / `sk_test_` keys. Fake card numbers. No real charges.
- **Live mode:** Uses `pk_live_` / `sk_live_` keys. Real money. Real cards.

Products, prices, customers, and webhook endpoints are **separate** between modes. You must re-create everything when switching to live mode.

**🚧 HUMAN GATE:** Activating live mode requires business verification in the Stripe dashboard. Cannot be done via CLI.

```bash
# Test card numbers for testing
# 4242424242424242 — Succeeds
# 4000000000009995 — Insufficient funds
# 4000000000000002 — Declined
```

## Fixtures (Bulk Product/Price Creation)

```bash
# Create a fixtures file for repeatable product setup
cat > stripe-fixtures.json << 'EOF'
{
  "_meta": { "template_version": 0 },
  "fixtures": [
    {
      "name": "pro_product",
      "path": "/v1/products",
      "method": "post",
      "params": {
        "name": "Pro Plan",
        "description": "Full access"
      }
    },
    {
      "name": "pro_monthly",
      "path": "/v1/prices",
      "method": "post",
      "params": {
        "product": "${pro_product:id}",
        "unit_amount": 2900,
        "currency": "usd",
        "recurring": { "interval": "month" }
      }
    }
  ]
}
EOF

# Execute fixtures
stripe fixtures stripe-fixtures.json
```

## Failure Modes

| Error | Cause | Fix |
|---|---|---|
| Webhook 400 `signature verification failed` | Wrong webhook secret | Check `STRIPE_WEBHOOK_SECRET` matches endpoint |
| `No such price: price_...` | Using test mode price with live keys (or vice versa) | Ensure keys and prices are from same mode |
| Checkout redirects to 404 | `success_url` path doesn't exist in app | Create the route or fix the URL |
| `stripe login` fails | Expired session | Re-run `stripe login` |
| Events not arriving | Webhook endpoint URL wrong or app not deployed | Check `stripe webhook_endpoints list` URL |
