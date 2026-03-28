# Blueprint: Next.js + Firebase + Stripe + Vercel

The Google ecosystem stack. Firebase provides auth and NoSQL database (Firestore), Vercel handles hosting, Stripe handles payments. This is architecturally different from the Supabase golden path: Firestore is document-based (not relational), Firebase Auth has built-in UI components, and Cloud Functions provide server-side logic that can run independently of your Next.js app.

**Services:** Firebase (Auth + Firestore + Cloud Functions), Stripe (payments), Vercel (hosting)
**Total time:** ~35 minutes agent-executed, ~10 minutes human gates
**Prerequisites:** Node.js 18+, npm, Git, Firebase CLI, Java 11+ (for emulators)

**When to use this instead of the golden path:**
- Your data model is document-oriented (nested objects, flexible schemas)
- You want Firebase's pre-built auth UI (FirebaseUI) and drop-in components
- You're already in the Google ecosystem (GCP, Google Analytics, BigQuery export)
- You need Firestore's real-time listeners (similar to Supabase Realtime, different API)
- You want Cloud Functions for background processing independent of your web app

**When NOT to use this:**
- You need relational data with complex joins (use Supabase/Neon + PostgreSQL)
- You want open-source / self-hostable infrastructure (Firebase is proprietary)
- You need row-level security at the database level (Firestore rules are powerful but different from RLS)
- Cost sensitivity at scale (Firestore read/write pricing can surprise you)

---

## Phase 0: Prerequisites & CLI Setup

### 0.1 Install CLIs

```bash
# Firebase CLI
npm install -g firebase-tools

# Vercel CLI
npm install -g vercel

# Stripe CLI
brew install stripe/stripe-cli/stripe

# Verify
firebase --version
vercel --version
stripe --version
```

### 0.2 Authenticate CLIs

```bash
# Firebase — opens browser
firebase login

# Vercel — opens browser
vercel login

# Stripe — opens browser
stripe login
```

**🚧 HUMAN GATE:** First-time Firebase requires a Google account. Stripe requires identity verification.

---

## Phase -1: Project Scaffolding (skip if you have code)

```bash
# Create Next.js app
npx create-next-app@latest my-firebase-app \
  --typescript --tailwind --eslint --app --src-dir --import-alias "@/*"

cd my-firebase-app

# Install Firebase SDKs
npm install firebase firebase-admin

# Install Stripe
npm install stripe @stripe/stripe-js

# Initialize git
git init && git add -A && git commit -m "Initial scaffold"
```

---

## Phase 1: Firebase Project Setup

### 1.1 Create Firebase Project

```bash
# Create project (globally unique ID required)
firebase projects:create my-firebase-app --display-name="My Firebase App"

# Set as active project
firebase use my-firebase-app
```

### 1.2 Initialize Firebase in the App

```bash
# Initialize Firebase services (non-interactive where possible)
firebase init firestore functions

# This creates:
# - firestore.rules
# - firestore.indexes.json
# - functions/ directory
```

**For functions setup, choose:**
- Language: TypeScript
- ESLint: Yes
- Install dependencies: Yes

### 1.3 Enable Auth Providers

**🚧 HUMAN GATE:** Auth provider configuration must be done in the Firebase console:
1. Go to console.firebase.google.com → your project → Authentication → Sign-in method
2. Enable **Email/Password**
3. Enable **Google** (automatically configured since it's a Google project)
4. (Optional) Enable **GitHub** — requires a GitHub OAuth App first (see `references/services/github-oauth.md`)

### 1.4 Get Firebase Config Values

```bash
# Get the web app config (creates a web app if none exists)
firebase apps:list

# If no web app exists:
firebase apps:create web "My Firebase Web App"

# Get the config object
firebase apps:sdkconfig web
# Output: firebaseConfig = { apiKey: "...", authDomain: "...", projectId: "...", ... }
```

Save these values — they go into env vars in Phase 4.

### 1.5 Get Stripe Keys

**🚧 HUMAN GATE:** Copy from dashboard.stripe.com/apikeys:
- Publishable key (pk_test_...)
- Secret key (sk_test_...)

### 1.6 Get Service Account Key (for Admin SDK)

**🚧 HUMAN GATE:**
1. Go to console.firebase.google.com → Project Settings → Service Accounts
2. Click "Generate New Private Key"
3. Save the JSON file securely — DO NOT commit to git

Extract the values you need:
```bash
# From the downloaded JSON, you need:
# - project_id
# - client_email
# - private_key (the long RSA key)
```

### Verification: Phase 1

```bash
echo "=== Phase 1 Verification ==="

# Firebase project exists
firebase projects:list | grep "my-firebase-app" && echo "Firebase project: ✅" || echo "Firebase project: ❌"

# Firestore initialized
[ -f firestore.rules ] && echo "Firestore rules: ✅" || echo "Firestore rules: ❌"

# Functions directory exists
[ -d functions ] && echo "Functions dir: ✅" || echo "Functions dir: ❌"

# Stripe connected
stripe config --list | grep "test" && echo "Stripe: ✅" || echo "Stripe: ❌"
```

---

## Phase 2: Firestore Schema & Rules

Firestore is schemaless — you don't write migrations. Instead, you define security rules and optionally create indexes for complex queries.

### 2.1 Write Firestore Rules

```bash
cat > firestore.rules << 'EOF'
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {

    // Users can read/write their own profile
    match /users/{userId} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
    }

    // Subscriptions — users can read their own, only server can write
    match /subscriptions/{subId} {
      allow read: if request.auth != null
        && resource.data.userId == request.auth.uid;
      // No client write — webhooks update via Admin SDK (bypasses rules)
    }

    // Products and prices are publicly readable
    match /products/{productId} {
      allow read: if true;
    }
    match /prices/{priceId} {
      allow read: if true;
    }
  }
}
EOF
```

### 2.2 Create Indexes

```bash
cat > firestore.indexes.json << 'EOF'
{
  "indexes": [
    {
      "collectionGroup": "subscriptions",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "userId", "order": "ASCENDING" },
        { "fieldPath": "status", "order": "ASCENDING" }
      ]
    }
  ],
  "fieldOverrides": []
}
EOF
```

### 2.3 Deploy Rules and Indexes

```bash
firebase deploy --only firestore:rules,firestore:indexes
```

### Verification: Phase 2

```bash
# Rules deployed successfully if the command above succeeded
echo "Phase 2: Firestore rules and indexes deployed ✅"
```

---

## Phase 3: Cloud Functions (Stripe Webhook Handler)

Firebase Cloud Functions handle Stripe webhooks independently of your Next.js app. This is a key architectural difference — webhook processing happens in Google's infrastructure, not in your Vercel deployment.

### 3.1 Install Stripe in Functions

```bash
cd functions
npm install stripe firebase-admin
cd ..
```

### 3.2 Write Webhook Handler

```bash
cat > functions/src/index.ts << 'EOF'
import { onRequest } from 'firebase-functions/v2/https';
import { initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import Stripe from 'stripe';

initializeApp();
const db = getFirestore();

const stripe = new Stripe(process.env.STRIPE_SECRET_KEY!, {
  apiVersion: '2024-12-18.acacia',
});

export const stripeWebhook = onRequest(async (req, res) => {
  const sig = req.headers['stripe-signature'] as string;
  let event: Stripe.Event;

  try {
    event = stripe.webhooks.constructEvent(
      req.rawBody,
      sig,
      process.env.STRIPE_WEBHOOK_SECRET!
    );
  } catch (err) {
    res.status(400).send('Webhook signature verification failed');
    return;
  }

  switch (event.type) {
    case 'checkout.session.completed': {
      const session = event.data.object as Stripe.Checkout.Session;
      if (session.metadata?.userId) {
        await db.collection('users').doc(session.metadata.userId).update({
          stripeCustomerId: session.customer,
        });
      }
      break;
    }
    case 'customer.subscription.created':
    case 'customer.subscription.updated': {
      const sub = event.data.object as Stripe.Subscription;
      await db.collection('subscriptions').doc(sub.id).set({
        userId: sub.metadata?.userId || '',
        status: sub.status,
        priceId: sub.items.data[0]?.price.id,
        currentPeriodEnd: new Date(sub.current_period_end * 1000),
        cancelAtPeriodEnd: sub.cancel_at_period_end,
      }, { merge: true });
      break;
    }
    case 'customer.subscription.deleted': {
      const sub = event.data.object as Stripe.Subscription;
      await db.collection('subscriptions').doc(sub.id).update({
        status: 'canceled',
      });
      break;
    }
  }

  res.json({ received: true });
});
EOF
```

### 3.3 Set Function Secrets

```bash
# Set Stripe secrets for Cloud Functions
firebase functions:secrets:set STRIPE_SECRET_KEY
# Enter: sk_test_...

firebase functions:secrets:set STRIPE_WEBHOOK_SECRET
# Enter: whsec_... (will be set after webhook creation in Phase 4)
```

### 3.4 Deploy Functions

```bash
firebase deploy --only functions
# Output: Function URL: https://us-central1-my-firebase-app.cloudfunctions.net/stripeWebhook
# SAVE THIS URL — it's your webhook endpoint
```

### Verification: Phase 3

```bash
# Check function deployed
firebase functions:log --limit=5

echo "Phase 3: Cloud Functions deployed ✅"
```

---

## Phase 4: Stripe Wiring

The webhook points to the Cloud Function URL (NOT Vercel). This is the key architectural difference — Stripe talks to Firebase directly.

### 4.1 Create Products & Prices

```bash
stripe products create \
  --name="Pro Plan" \
  --description="Full access"
# Save prod_...

stripe prices create \
  --product=<product-id> \
  --unit-amount=2900 \
  --currency=usd \
  -d "recurring[interval]=month"
# Save price_...
```

### 4.2 Create Webhook Endpoint

**Important:** The URL points to your Cloud Function, not Vercel:

```bash
stripe webhook_endpoints create \
  --url="https://us-central1-my-firebase-app.cloudfunctions.net/stripeWebhook" \
  --enabled-events="checkout.session.completed" \
  --enabled-events="customer.subscription.created" \
  --enabled-events="customer.subscription.updated" \
  --enabled-events="customer.subscription.deleted"

# Save whsec_... and update the function secret:
firebase functions:secrets:set STRIPE_WEBHOOK_SECRET
# Enter: whsec_...

# Redeploy functions to pick up the new secret
firebase deploy --only functions
```

### Verification: Phase 4

```bash
# Test webhook delivery
stripe trigger checkout.session.completed

# Check function logs for the event
firebase functions:log --limit=5

echo "Phase 4: Stripe wired to Cloud Functions ✅"
```

---

## Phase 5: Vercel Deployment

Deploy the Next.js frontend to Vercel. It only needs client-side Firebase config and Stripe publishable key — all server-side Stripe handling is in Cloud Functions.

### 5.1 Deploy to Vercel

```bash
vercel --yes
# Save deployment URL
```

### 5.2 Set Environment Variables

```bash
# Firebase client config (public — safe to expose)
vercel env add NEXT_PUBLIC_FIREBASE_API_KEY production preview development <<< "<api-key>"
vercel env add NEXT_PUBLIC_FIREBASE_AUTH_DOMAIN production preview development <<< "my-firebase-app.firebaseapp.com"
vercel env add NEXT_PUBLIC_FIREBASE_PROJECT_ID production preview development <<< "my-firebase-app"
vercel env add NEXT_PUBLIC_FIREBASE_STORAGE_BUCKET production preview development <<< "my-firebase-app.appspot.com"
vercel env add NEXT_PUBLIC_FIREBASE_MESSAGING_SENDER_ID production preview development <<< "<sender-id>"
vercel env add NEXT_PUBLIC_FIREBASE_APP_ID production preview development <<< "<app-id>"

# Stripe publishable key (public)
vercel env add NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY production preview development <<< "pk_test_..."

# Firebase Admin (server-side routes in Next.js, if needed)
vercel env add FIREBASE_PROJECT_ID production <<< "my-firebase-app"
vercel env add FIREBASE_CLIENT_EMAIL production <<< "<client-email-from-service-account>"
vercel env add FIREBASE_PRIVATE_KEY production <<< "<private-key-from-service-account>"

# Stripe secret (for server-side checkout session creation)
vercel env add STRIPE_SECRET_KEY production <<< "sk_test_..."

# App URL
vercel env add NEXT_PUBLIC_APP_URL production <<< "https://<your-vercel-url>"
```

### 5.3 Add Auth Domain

**🚧 HUMAN GATE:** Add your Vercel deployment domain to Firebase Auth authorized domains:
1. console.firebase.google.com → Authentication → Settings → Authorized domains
2. Add: `<your-vercel-url>` and your custom domain if applicable

### 5.4 Production Deploy

```bash
vercel --prod --yes
```

### Verification: Phase 5

```bash
DEPLOY_URL="https://my-firebase-app.vercel.app"  # replace

STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$DEPLOY_URL")
echo "Vercel: HTTP $STATUS $([ '$STATUS' = '200' ] && echo '✅' || echo '❌')"

vercel env ls | head -20
echo "Phase 5: Vercel deployed ✅"
```

---

## Phase 6: Final Verification

```bash
echo "==========================================="
echo "  FIREBASE STACK VERIFICATION"
echo "==========================================="

DEPLOY_URL="https://my-firebase-app.vercel.app"

# 1. Vercel
echo ""
echo "--- Vercel ---"
STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$DEPLOY_URL")
echo "Deployment: HTTP $STATUS $([ '$STATUS' = '200' ] && echo '✅' || echo '❌')"

# 2. Firebase Functions
echo ""
echo "--- Cloud Functions ---"
FUNC_URL="https://us-central1-my-firebase-app.cloudfunctions.net/stripeWebhook"
FUNC_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$FUNC_URL")
echo "Webhook endpoint: HTTP $FUNC_STATUS (405 = exists but needs Stripe signature)"

# 3. Stripe
echo ""
echo "--- Stripe ---"
PRODUCTS=$(stripe products list --limit=1 2>/dev/null | grep -c "id")
echo "Products: $([ $PRODUCTS -gt 0 ] && echo '✅' || echo '❌')"

WEBHOOKS=$(stripe webhook_endpoints list 2>/dev/null | grep -c "cloudfunctions.net")
echo "Webhook → Cloud Functions: $([ $WEBHOOKS -gt 0 ] && echo '✅' || echo '❌')"

echo ""
echo "==========================================="
```

---

## Key Differences from the Golden Path

| Aspect | Golden Path (Supabase) | Firebase Stack |
|---|---|---|
| Database | PostgreSQL (relational) | Firestore (document/NoSQL) |
| Schema | Migrations + typed columns | Schemaless (rules enforce structure) |
| Auth | Supabase Auth | Firebase Auth |
| Webhooks run on | Vercel (same app) | Cloud Functions (separate infra) |
| Security model | Row-Level Security (SQL) | Firestore Rules (custom language) |
| Real-time | Supabase Realtime | Firestore onSnapshot |
| Vendor coupling | Moderate (Supabase is open source) | High (Firebase is proprietary) |
| Free tier | Generous (Supabase free tier) | Generous (Spark plan, but Functions need Blaze) |

## Adding Auth UI

Firebase has pre-built auth UI components:

```bash
npm install firebaseui react-firebaseui
```

This gives you a drop-in `<StyledFirebaseAuth>` component with Google, GitHub, Email/Password sign-in — no custom auth forms needed.
