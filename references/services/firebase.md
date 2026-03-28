# Service Reference: Firebase

Firebase provides Authentication, Firestore (NoSQL database), Realtime Database, Cloud Functions, Hosting, Cloud Storage, and Analytics. It's Google's full-stack app platform.

## CLI Authentication

```bash
# Install Firebase CLI
npm install -g firebase-tools

# Login (opens browser)
firebase login

# Login non-interactively (CI/agents)
firebase login:ci
# Returns a refresh token — set as FIREBASE_TOKEN env var

# Or use a service account key
export GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account-key.json

# Check current auth
firebase login:list

# Logout
firebase logout
```

**Getting a service account key:** 🚧 HUMAN GATE — Create at console.firebase.google.com > Project Settings > Service Accounts > Generate New Private Key. This JSON file enables fully non-interactive CLI usage.

## Project Management

```bash
# List available projects
firebase projects:list

# Create a new project
firebase projects:create <project-id> --display-name="My App"
# Note: project-id must be globally unique across all of Firebase

# Initialize Firebase in current directory
firebase init
# Interactive — selects services (Firestore, Functions, Hosting, etc.)

# Non-interactive init (specify services)
firebase init firestore functions hosting --project=<project-id>

# Set active project
firebase use <project-id>

# Add project alias
firebase use --add
# Creates .firebaserc with aliases
```

## Firestore (NoSQL Database)

```bash
# Deploy Firestore rules
firebase deploy --only firestore:rules

# Deploy Firestore indexes
firebase deploy --only firestore:indexes

# Export Firestore data
firebase firestore:delete --all-collections  # DANGER: deletes everything

# Import/export via gcloud (for backups)
gcloud firestore export gs://<bucket-name>/backups/$(date +%Y%m%d)
gcloud firestore import gs://<bucket-name>/backups/<timestamp>
```

### Firestore Rules (firestore.rules)

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {

    // Authenticated users read/write their own data
    match /users/{userId} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
    }

    // Public read, authenticated write
    match /posts/{postId} {
      allow read: if true;
      allow create: if request.auth != null;
      allow update, delete: if request.auth != null
        && request.auth.uid == resource.data.authorId;
    }
  }
}
```

### Firestore Indexes (firestore.indexes.json)

```json
{
  "indexes": [
    {
      "collectionGroup": "posts",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "authorId", "order": "ASCENDING" },
        { "fieldPath": "createdAt", "order": "DESCENDING" }
      ]
    }
  ]
}
```

## Firebase Authentication

Auth is primarily configured via the Firebase console, but some operations are available via CLI and Admin SDK.

```bash
# Enable auth providers via Firebase console
# 🚧 HUMAN GATE — Provider configuration (Google, GitHub, Email/Password)
# must be done at console.firebase.google.com > Authentication > Sign-in method

# Export auth users
firebase auth:export users.json --format=json

# Import auth users
firebase auth:import users.json
```

### Auth in App Code (Web SDK)

```typescript
import { getAuth, signInWithPopup, GoogleAuthProvider } from 'firebase/auth';

const auth = getAuth();
const provider = new GoogleAuthProvider();

// Sign in
const result = await signInWithPopup(auth, provider);
const user = result.user;

// Get ID token (for backend verification)
const idToken = await user.getIdToken();
```

## Cloud Functions

```bash
# Deploy all functions
firebase deploy --only functions

# Deploy a specific function
firebase deploy --only functions:myFunctionName

# View function logs
firebase functions:log

# Delete a function
firebase functions:delete myFunctionName

# Set function config/secrets
firebase functions:config:set stripe.key="sk_test_..."
firebase functions:config:get

# For 2nd gen functions, use Secret Manager instead:
firebase functions:secrets:set STRIPE_KEY
```

### Function Template (2nd Gen / v2)

```typescript
// functions/src/index.ts
import { onRequest } from 'firebase-functions/v2/https';
import { onDocumentCreated } from 'firebase-functions/v2/firestore';

// HTTP function
export const api = onRequest(async (req, res) => {
  res.json({ status: 'ok' });
});

// Firestore trigger
export const onUserCreated = onDocumentCreated('users/{userId}', async (event) => {
  const snapshot = event.data;
  const userData = snapshot?.data();
  // Send welcome email, etc.
});
```

## Firebase Hosting

```bash
# Deploy hosting only
firebase deploy --only hosting

# Preview channel (temporary URL for testing)
firebase hosting:channel:deploy preview-name
# Output: https://<project-id>--preview-name-<hash>.web.app

# List channels
firebase hosting:channel:list

# Delete preview channel
firebase hosting:channel:delete preview-name
```

### firebase.json (Hosting Config)

```json
{
  "hosting": {
    "public": "out",
    "ignore": ["firebase.json", "**/.*", "**/node_modules/**"],
    "rewrites": [
      { "source": "/api/**", "function": "api" },
      { "source": "**", "destination": "/index.html" }
    ],
    "headers": [
      {
        "source": "**/*.@(js|css)",
        "headers": [{ "key": "Cache-Control", "value": "max-age=31536000" }]
      }
    ]
  },
  "firestore": {
    "rules": "firestore.rules",
    "indexes": "firestore.indexes.json"
  },
  "functions": {
    "source": "functions",
    "runtime": "nodejs20"
  }
}
```

## Cloud Storage

```bash
# Deploy storage rules
firebase deploy --only storage

# Upload via gsutil
gsutil cp local-file.png gs://<project-id>.appspot.com/uploads/

# List bucket contents
gsutil ls gs://<project-id>.appspot.com/

# Set CORS on bucket
gsutil cors set cors.json gs://<project-id>.appspot.com
```

## Emulators (Local Development)

```bash
# Start all emulators
firebase emulators:start

# Start specific emulators
firebase emulators:start --only auth,firestore,functions

# Start with data import
firebase emulators:start --import=./emulator-data

# Export emulator data on shutdown
firebase emulators:start --export-on-exit=./emulator-data

# Emulator UI available at http://localhost:4000
```

## Common Patterns

### Next.js + Firebase

```typescript
// lib/firebase.ts — client-side initialization
import { initializeApp, getApps } from 'firebase/app';
import { getAuth } from 'firebase/auth';
import { getFirestore } from 'firebase/firestore';

const firebaseConfig = {
  apiKey: process.env.NEXT_PUBLIC_FIREBASE_API_KEY,
  authDomain: process.env.NEXT_PUBLIC_FIREBASE_AUTH_DOMAIN,
  projectId: process.env.NEXT_PUBLIC_FIREBASE_PROJECT_ID,
  storageBucket: process.env.NEXT_PUBLIC_FIREBASE_STORAGE_BUCKET,
  messagingSenderId: process.env.NEXT_PUBLIC_FIREBASE_MESSAGING_SENDER_ID,
  appId: process.env.NEXT_PUBLIC_FIREBASE_APP_ID,
};

const app = getApps().length === 0 ? initializeApp(firebaseConfig) : getApps()[0];
export const auth = getAuth(app);
export const db = getFirestore(app);
```

### Admin SDK (Server-Side)

```typescript
// lib/firebase-admin.ts
import { initializeApp, cert, getApps } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { getAuth } from 'firebase-admin/auth';

if (getApps().length === 0) {
  initializeApp({
    credential: cert({
      projectId: process.env.FIREBASE_PROJECT_ID,
      clientEmail: process.env.FIREBASE_CLIENT_EMAIL,
      privateKey: process.env.FIREBASE_PRIVATE_KEY?.replace(/\\n/g, '\n'),
    }),
  });
}

export const adminDb = getFirestore();
export const adminAuth = getAuth();
```

## Required Environment Variables

```bash
# Client-side (NEXT_PUBLIC_ prefix for Next.js)
NEXT_PUBLIC_FIREBASE_API_KEY=
NEXT_PUBLIC_FIREBASE_AUTH_DOMAIN=<project-id>.firebaseapp.com
NEXT_PUBLIC_FIREBASE_PROJECT_ID=
NEXT_PUBLIC_FIREBASE_STORAGE_BUCKET=<project-id>.appspot.com
NEXT_PUBLIC_FIREBASE_MESSAGING_SENDER_ID=
NEXT_PUBLIC_FIREBASE_APP_ID=

# Server-side (Admin SDK)
FIREBASE_PROJECT_ID=
FIREBASE_CLIENT_EMAIL=
FIREBASE_PRIVATE_KEY=
```

**Getting these values:** Run `firebase apps:sdkconfig web` to output the client config object. For the Admin SDK, use the service account JSON from the human gate step above.

## Dependency Position

- **Depends on:** Google Cloud project (auto-created with Firebase project).
- **Depended on by:** Apps using Firebase Auth, Firestore, or Hosting.
- **Layer 1 candidate:** Create project and configure auth providers early.
- **Layer 2 candidate:** Deploy to Firebase Hosting for a URL.
- **Layer 3:** Wire auth redirect domains, function triggers, storage CORS.

## Failure Modes

| Error | Cause | Fix |
|---|---|---|
| `PERMISSION_DENIED` | Firestore rules blocking access | Check firestore.rules, ensure auth state matches |
| `NOT_FOUND` for project | Wrong project ID or not initialized | `firebase use <correct-project-id>` |
| `Functions deploy failed` | Node version mismatch | Check `engines` in functions/package.json matches runtime |
| `Quota exceeded` | Hit free tier limits (Spark plan) | Upgrade to Blaze plan (pay-as-you-go) |
| `Auth domain not authorized` | Deployment domain not in authorized list | Add domain at console > Auth > Settings > Authorized domains |
| `Private key parsing error` | Newlines in FIREBASE_PRIVATE_KEY | Ensure `\n` in the key is actual newlines: `.replace(/\\n/g, '\n')` |
| `Emulators fail to start` | Port conflicts | Check ports 4000, 8080, 9099, 5001 are free |
