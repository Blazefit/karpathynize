#!/bin/bash
# provision_env.sh — Collect and inject environment variables for a stack
#
# This script walks you through collecting all the secrets and config values
# needed for a stack, validates them, and writes them to .env.local and/or
# pushes them to Vercel/Cloudflare.
#
# Usage:
#   ./provision_env.sh                    # Interactive — asks for each value
#   ./provision_env.sh --from-env .env    # Import from an existing env file
#   ./provision_env.sh --push vercel      # Push .env.local values to Vercel
#   ./provision_env.sh --push cloudflare  # Push to Cloudflare Pages
#   ./provision_env.sh --validate         # Validate all values in .env.local
#
# This script does NOT create accounts or provision services. It handles
# the last-mile problem: getting the right values into the right places.

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

MODE="${1:---interactive}"
TARGET="${2:-}"

ENV_FILE=".env.local"

# === Stack Templates ===
# Each template defines required and optional vars with validation patterns

declare -A VAR_PATTERNS
VAR_PATTERNS=(
  # Supabase
  ["NEXT_PUBLIC_SUPABASE_URL"]="^https://[a-z]+\.supabase\.co$"
  ["NEXT_PUBLIC_SUPABASE_ANON_KEY"]="^eyJ"
  ["SUPABASE_SERVICE_ROLE_KEY"]="^eyJ"

  # Stripe
  ["NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY"]="^pk_(test|live)_"
  ["STRIPE_SECRET_KEY"]="^sk_(test|live)_"
  ["STRIPE_WEBHOOK_SECRET"]="^whsec_"

  # Firebase
  ["NEXT_PUBLIC_FIREBASE_API_KEY"]="^AIza"
  ["NEXT_PUBLIC_FIREBASE_PROJECT_ID"]="^[a-z0-9-]+$"
  ["NEXT_PUBLIC_FIREBASE_AUTH_DOMAIN"]="\.firebaseapp\.com$"

  # Cloudflare
  ["CLOUDFLARE_API_TOKEN"]="^[a-zA-Z0-9_-]{40}"

  # Clerk
  ["NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY"]="^pk_(test|live)_"
  ["CLERK_SECRET_KEY"]="^sk_(test|live)_"

  # Resend
  ["RESEND_API_KEY"]="^re_"

  # PostHog
  ["NEXT_PUBLIC_POSTHOG_KEY"]="^phc_"

  # Linear
  ["LINEAR_API_KEY"]="^lin_api_"

  # GitHub
  ["GITHUB_CLIENT_ID"]="^(Iv|Ov)"
  ["GITHUB_CLIENT_SECRET"]="^[a-f0-9]{40}$"

  # General
  ["NEXT_PUBLIC_APP_URL"]="^https?://"
)

declare -A VAR_DESCRIPTIONS
VAR_DESCRIPTIONS=(
  ["NEXT_PUBLIC_SUPABASE_URL"]="Supabase project URL (e.g., https://abc123.supabase.co)"
  ["NEXT_PUBLIC_SUPABASE_ANON_KEY"]="Supabase anonymous/public key (starts with eyJ)"
  ["SUPABASE_SERVICE_ROLE_KEY"]="Supabase service role key (starts with eyJ, KEEP SECRET)"
  ["NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY"]="Stripe publishable key (pk_test_... or pk_live_...)"
  ["STRIPE_SECRET_KEY"]="Stripe secret key (sk_test_... or sk_live_...)"
  ["STRIPE_WEBHOOK_SECRET"]="Stripe webhook signing secret (whsec_...)"
  ["NEXT_PUBLIC_FIREBASE_API_KEY"]="Firebase web API key (starts with AIza)"
  ["NEXT_PUBLIC_FIREBASE_PROJECT_ID"]="Firebase project ID (lowercase alphanumeric + hyphens)"
  ["NEXT_PUBLIC_FIREBASE_AUTH_DOMAIN"]="Firebase auth domain (projectid.firebaseapp.com)"
  ["NEXT_PUBLIC_APP_URL"]="Your app's public URL (https://...)"
  ["RESEND_API_KEY"]="Resend API key (re_...)"
  ["NEXT_PUBLIC_POSTHOG_KEY"]="PostHog project API key (phc_...)"
  ["LINEAR_API_KEY"]="Linear personal API key (lin_api_...)"
  ["GITHUB_CLIENT_ID"]="GitHub OAuth App client ID"
  ["GITHUB_CLIENT_SECRET"]="GitHub OAuth App client secret"
)

# === Stack Detection ===
detect_stack() {
  local vars=()

  # Check package.json for dependencies
  if [ -f "package.json" ]; then
    local pkg=$(cat package.json)

    if echo "$pkg" | grep -q "@supabase/supabase-js"; then
      vars+=("NEXT_PUBLIC_SUPABASE_URL" "NEXT_PUBLIC_SUPABASE_ANON_KEY" "SUPABASE_SERVICE_ROLE_KEY")
    fi

    if echo "$pkg" | grep -q "\"stripe\""; then
      vars+=("NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY" "STRIPE_SECRET_KEY" "STRIPE_WEBHOOK_SECRET")
    fi

    if echo "$pkg" | grep -q "\"firebase\""; then
      vars+=("NEXT_PUBLIC_FIREBASE_API_KEY" "NEXT_PUBLIC_FIREBASE_AUTH_DOMAIN" "NEXT_PUBLIC_FIREBASE_PROJECT_ID")
    fi

    if echo "$pkg" | grep -q "@clerk"; then
      vars+=("NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY" "CLERK_SECRET_KEY")
    fi

    if echo "$pkg" | grep -q "resend"; then
      vars+=("RESEND_API_KEY")
    fi

    if echo "$pkg" | grep -q "posthog"; then
      vars+=("NEXT_PUBLIC_POSTHOG_KEY")
    fi
  fi

  # Always include app URL
  vars+=("NEXT_PUBLIC_APP_URL")

  echo "${vars[@]}"
}

# === Validation ===
validate_var() {
  local name="$1"
  local value="$2"

  local pattern="${VAR_PATTERNS[$name]:-}"
  if [ -z "$pattern" ]; then
    # No pattern — just check it's not empty
    [ -n "$value" ] && return 0 || return 1
  fi

  echo "$value" | grep -qE "$pattern"
}

# === Modes ===

interactive() {
  echo -e "${CYAN}Provisioning environment variables...${NC}"
  echo ""

  # Detect required vars from project
  local detected_vars=($(detect_stack))

  if [ ${#detected_vars[@]} -eq 0 ]; then
    echo -e "${YELLOW}No package.json found or no recognized dependencies.${NC}"
    echo "Specify vars manually or run from your project root."
    exit 1
  fi

  echo "Detected stack dependencies. Need these env vars:"
  for var in "${detected_vars[@]}"; do
    local desc="${VAR_DESCRIPTIONS[$var]:-$var}"
    echo -e "  - ${CYAN}$var${NC}: $desc"
  done
  echo ""

  # Load existing values if .env.local exists
  if [ -f "$ENV_FILE" ]; then
    echo -e "${GREEN}Found existing $ENV_FILE — will preserve existing values.${NC}"
    set -a
    source "$ENV_FILE" 2>/dev/null || true
    set +a
    echo ""
  fi

  # Collect values
  local new_vars=()
  for var in "${detected_vars[@]}"; do
    local existing="${!var:-}"
    local desc="${VAR_DESCRIPTIONS[$var]:-}"

    if [ -n "$existing" ]; then
      if validate_var "$var" "$existing"; then
        echo -e "  ${GREEN}✅${NC} $var = ${existing:0:15}... (existing, valid)"
        continue
      else
        echo -e "  ${YELLOW}⚠️${NC}  $var = ${existing:0:15}... (existing but INVALID format)"
      fi
    fi

    echo -n "  Enter $var"
    [ -n "$desc" ] && echo -n " ($desc)"
    echo -n ": "
    read -r value

    if [ -z "$value" ]; then
      echo -e "    ${YELLOW}Skipped${NC}"
      continue
    fi

    if validate_var "$var" "$value"; then
      new_vars+=("$var=$value")
      echo -e "    ${GREEN}✅ Valid${NC}"
    else
      echo -e "    ${YELLOW}⚠️  Warning: Value doesn't match expected pattern. Saving anyway.${NC}"
      new_vars+=("$var=$value")
    fi
  done

  # Write to .env.local
  if [ ${#new_vars[@]} -gt 0 ]; then
    echo ""
    echo -e "${CYAN}Writing to $ENV_FILE...${NC}"

    for entry in "${new_vars[@]}"; do
      local key="${entry%%=*}"
      local val="${entry#*=}"

      # Remove existing line if present, then append
      if [ -f "$ENV_FILE" ]; then
        grep -v "^${key}=" "$ENV_FILE" > "${ENV_FILE}.tmp" 2>/dev/null || true
        mv "${ENV_FILE}.tmp" "$ENV_FILE"
      fi

      echo "${key}=${val}" >> "$ENV_FILE"
    done

    echo -e "${GREEN}Done! ${#new_vars[@]} variable(s) written to $ENV_FILE${NC}"
  else
    echo -e "${GREEN}No new variables needed.${NC}"
  fi
}

validate() {
  echo -e "${CYAN}Validating $ENV_FILE...${NC}"
  echo ""

  if [ ! -f "$ENV_FILE" ]; then
    echo -e "${RED}$ENV_FILE not found${NC}"
    exit 1
  fi

  set -a
  source "$ENV_FILE"
  set +a

  local total=0
  local valid=0
  local invalid=0

  while IFS='=' read -r key value; do
    # Skip comments and empty lines
    [[ "$key" =~ ^#.*$ ]] && continue
    [ -z "$key" ] && continue

    total=$((total + 1))

    if validate_var "$key" "$value"; then
      echo -e "  ${GREEN}✅${NC} $key = ${value:0:15}..."
      valid=$((valid + 1))
    else
      echo -e "  ${RED}❌${NC} $key = ${value:0:15}... (invalid format)"
      invalid=$((invalid + 1))
    fi
  done < "$ENV_FILE"

  echo ""
  echo "Valid: $valid | Invalid: $invalid | Total: $total"

  [ "$invalid" -eq 0 ] && exit 0 || exit 1
}

push_vercel() {
  echo -e "${CYAN}Pushing $ENV_FILE to Vercel...${NC}"
  echo ""

  if ! command -v vercel &> /dev/null; then
    echo -e "${RED}Vercel CLI not installed${NC}"
    exit 1
  fi

  if [ ! -f "$ENV_FILE" ]; then
    echo -e "${RED}$ENV_FILE not found${NC}"
    exit 1
  fi

  local pushed=0

  while IFS='=' read -r key value; do
    [[ "$key" =~ ^#.*$ ]] && continue
    [ -z "$key" ] && continue
    [ -z "$value" ] && continue

    # Determine environments
    local envs="production"
    if [[ "$key" == NEXT_PUBLIC_* ]]; then
      envs="production preview development"
    fi

    echo -n "  Pushing $key to $envs... "
    echo "$value" | vercel env add "$key" $envs --force 2>/dev/null && \
      echo -e "${GREEN}✅${NC}" || echo -e "${RED}❌${NC}"

    pushed=$((pushed + 1))
  done < "$ENV_FILE"

  echo ""
  echo -e "${GREEN}Pushed $pushed variable(s) to Vercel.${NC}"
  echo -e "${YELLOW}Remember to redeploy: vercel --prod --yes${NC}"
}

push_cloudflare() {
  echo -e "${CYAN}Pushing $ENV_FILE to Cloudflare Pages...${NC}"
  echo ""

  if ! command -v wrangler &> /dev/null; then
    echo -e "${RED}Wrangler CLI not installed${NC}"
    exit 1
  fi

  local project_name=""
  if [ -f "wrangler.toml" ]; then
    project_name=$(grep "^name" wrangler.toml | head -1 | sed 's/.*= *"//;s/"//')
  fi

  if [ -z "$project_name" ]; then
    echo -n "  Enter Cloudflare Pages project name: "
    read -r project_name
  fi

  echo "  Project: $project_name"
  echo ""

  local pushed=0

  while IFS='=' read -r key value; do
    [[ "$key" =~ ^#.*$ ]] && continue
    [ -z "$key" ] && continue
    [ -z "$value" ] && continue

    # Secret vars use wrangler pages secret, public vars use env vars API
    if [[ "$key" == NEXT_PUBLIC_* ]]; then
      echo -n "  $key (public)... "
    else
      echo -n "  $key (secret)... "
    fi

    echo "$value" | wrangler pages secret put "$key" --project-name="$project_name" 2>/dev/null && \
      echo -e "${GREEN}✅${NC}" || echo -e "${RED}❌${NC}"

    pushed=$((pushed + 1))
  done < "$ENV_FILE"

  echo ""
  echo -e "${GREEN}Pushed $pushed variable(s) to Cloudflare Pages ($project_name).${NC}"
  echo -e "${YELLOW}Remember to redeploy.${NC}"
}

from_env() {
  local source_file="$TARGET"

  if [ ! -f "$source_file" ]; then
    echo -e "${RED}File not found: $source_file${NC}"
    exit 1
  fi

  echo -e "${CYAN}Importing from $source_file to $ENV_FILE...${NC}"

  local imported=0
  while IFS='=' read -r key value; do
    [[ "$key" =~ ^#.*$ ]] && continue
    [ -z "$key" ] && continue

    if validate_var "$key" "$value"; then
      echo -e "  ${GREEN}✅${NC} $key"
    else
      echo -e "  ${YELLOW}���️${NC}  $key (unrecognized pattern, imported anyway)"
    fi

    # Append/update in .env.local
    if [ -f "$ENV_FILE" ]; then
      grep -v "^${key}=" "$ENV_FILE" > "${ENV_FILE}.tmp" 2>/dev/null || true
      mv "${ENV_FILE}.tmp" "$ENV_FILE"
    fi
    echo "${key}=${value}" >> "$ENV_FILE"

    imported=$((imported + 1))
  done < "$source_file"

  echo ""
  echo -e "${GREEN}Imported $imported variable(s) to $ENV_FILE${NC}"
}

# === Route ===
case "$MODE" in
  --interactive|-i)
    interactive
    ;;
  --validate|-v)
    validate
    ;;
  --push|-p)
    case "$TARGET" in
      vercel) push_vercel ;;
      cloudflare) push_cloudflare ;;
      *)
        echo "Usage: $0 --push [vercel|cloudflare]"
        exit 1
        ;;
    esac
    ;;
  --from-env|-f)
    from_env
    ;;
  --help|-h)
    echo "Usage: $0 [mode] [target]"
    echo ""
    echo "Modes:"
    echo "  --interactive, -i    Collect env vars interactively (default)"
    echo "  --validate, -v       Validate all values in .env.local"
    echo "  --push, -p           Push .env.local to a deployment platform"
    echo "                       Targets: vercel, cloudflare"
    echo "  --from-env, -f       Import from another env file"
    echo "                       e.g., $0 --from-env .env.production"
    echo ""
    echo "This script detects your stack from package.json and knows"
    echo "the expected format for each service's env vars."
    ;;
  *)
    interactive
    ;;
esac
