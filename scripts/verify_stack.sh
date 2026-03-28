#!/bin/bash
# verify_stack.sh — Verify all services are connected and working
# Usage: ./verify_stack.sh [--env-file .env.local]
#
# This script checks:
# 1. All required env vars are set
# 2. Supabase API is reachable and tables exist
# 3. Vercel deployment is live
# 4. Stripe CLI is connected and products/webhooks are configured
# 5. (Optional) Resend domain is verified

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

PASS="${GREEN}✅${NC}"
FAIL="${RED}❌${NC}"
WARN="${YELLOW}⚠️${NC}"

# Load env file if specified
ENV_FILE="${1:-.env.local}"
if [ -f "$ENV_FILE" ]; then
  set -a
  source "$ENV_FILE"
  set +a
  echo "Loaded environment from $ENV_FILE"
fi

echo ""
echo "==========================================="
echo "  STACK VERIFICATION REPORT"
echo "  $(date '+%Y-%m-%d %H:%M:%S')"
echo "==========================================="

TOTAL=0
PASSED=0
FAILED=0
WARNINGS=0

check() {
  TOTAL=$((TOTAL + 1))
  if [ "$1" = "pass" ]; then
    PASSED=$((PASSED + 1))
    echo -e "  $PASS $2"
  elif [ "$1" = "warn" ]; then
    WARNINGS=$((WARNINGS + 1))
    echo -e "  $WARN $2"
  else
    FAILED=$((FAILED + 1))
    echo -e "  $FAIL $2"
  fi
}

# === 1. ENVIRONMENT VARIABLES ===
echo ""
echo "--- Environment Variables ---"

REQUIRED_VARS=(
  "NEXT_PUBLIC_SUPABASE_URL"
  "NEXT_PUBLIC_SUPABASE_ANON_KEY"
  "SUPABASE_SERVICE_ROLE_KEY"
  "NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY"
  "STRIPE_SECRET_KEY"
  "STRIPE_WEBHOOK_SECRET"
)

OPTIONAL_VARS=(
  "NEXT_PUBLIC_APP_URL"
  "RESEND_API_KEY"
)

for VAR in "${REQUIRED_VARS[@]}"; do
  if [ -n "${!VAR:-}" ]; then
    VALUE="${!VAR}"
    check "pass" "$VAR = ${VALUE:0:12}..."
  else
    check "fail" "$VAR is MISSING"
  fi
done

for VAR in "${OPTIONAL_VARS[@]}"; do
  if [ -n "${!VAR:-}" ]; then
    VALUE="${!VAR}"
    check "pass" "$VAR = ${VALUE:0:12}... (optional)"
  else
    check "warn" "$VAR not set (optional)"
  fi
done

# === 2. SUPABASE ===
echo ""
echo "--- Supabase ---"

if [ -n "${NEXT_PUBLIC_SUPABASE_URL:-}" ] && [ -n "${NEXT_PUBLIC_SUPABASE_ANON_KEY:-}" ]; then
  # API health check
  HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
    "${NEXT_PUBLIC_SUPABASE_URL}/rest/v1/" \
    -H "apikey: ${NEXT_PUBLIC_SUPABASE_ANON_KEY}" \
    -H "Authorization: Bearer ${NEXT_PUBLIC_SUPABASE_ANON_KEY}" \
    2>/dev/null || echo "000")

  if [ "$HTTP_STATUS" = "200" ]; then
    check "pass" "Supabase API reachable (HTTP $HTTP_STATUS)"
  else
    check "fail" "Supabase API unreachable (HTTP $HTTP_STATUS)"
  fi

  # Check key tables
  for TABLE in profiles subscriptions products prices; do
    TABLE_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
      "${NEXT_PUBLIC_SUPABASE_URL}/rest/v1/${TABLE}?select=count&limit=0" \
      -H "apikey: ${NEXT_PUBLIC_SUPABASE_ANON_KEY}" \
      -H "Authorization: Bearer ${NEXT_PUBLIC_SUPABASE_ANON_KEY}" \
      2>/dev/null || echo "000")

    if [ "$TABLE_STATUS" = "200" ] || [ "$TABLE_STATUS" = "206" ]; then
      check "pass" "Table '$TABLE' exists and accessible"
    else
      check "fail" "Table '$TABLE' missing or inaccessible (HTTP $TABLE_STATUS)"
    fi
  done
else
  check "fail" "Supabase: Cannot test — env vars missing"
fi

# === 3. VERCEL ===
echo ""
echo "--- Vercel ---"

if command -v vercel &> /dev/null; then
  check "pass" "Vercel CLI installed"

  # Check if project is linked
  if [ -d ".vercel" ]; then
    check "pass" "Vercel project linked"
  else
    check "warn" "Vercel project not linked in current directory"
  fi
else
  check "fail" "Vercel CLI not installed"
fi

if [ -n "${NEXT_PUBLIC_APP_URL:-}" ]; then
  VERCEL_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "${NEXT_PUBLIC_APP_URL}" 2>/dev/null || echo "000")
  if [ "$VERCEL_STATUS" = "200" ] || [ "$VERCEL_STATUS" = "308" ] || [ "$VERCEL_STATUS" = "307" ]; then
    check "pass" "Deployment live at ${NEXT_PUBLIC_APP_URL} (HTTP $VERCEL_STATUS)"
  else
    check "fail" "Deployment not responding at ${NEXT_PUBLIC_APP_URL} (HTTP $VERCEL_STATUS)"
  fi
fi

# === 4. STRIPE ===
echo ""
echo "--- Stripe ---"

if command -v stripe &> /dev/null; then
  check "pass" "Stripe CLI installed"

  # Check products
  PRODUCT_COUNT=$(stripe products list --limit=100 2>/dev/null | grep -c '"id"' || echo "0")
  if [ "$PRODUCT_COUNT" -gt 0 ]; then
    check "pass" "Stripe products configured ($PRODUCT_COUNT found)"
  else
    check "warn" "No Stripe products found (create products before launch)"
  fi

  # Check webhooks
  WEBHOOK_COUNT=$(stripe webhook_endpoints list 2>/dev/null | grep -c '"url"' || echo "0")
  if [ "$WEBHOOK_COUNT" -gt 0 ]; then
    check "pass" "Stripe webhooks configured ($WEBHOOK_COUNT endpoint(s))"
  else
    check "fail" "No Stripe webhook endpoints configured"
  fi
else
  check "fail" "Stripe CLI not installed"
fi

# === 5. RESEND (Optional) ===
echo ""
echo "--- Resend (Optional) ---"

if [ -n "${RESEND_API_KEY:-}" ]; then
  RESEND_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
    "https://api.resend.com/domains" \
    -H "Authorization: Bearer ${RESEND_API_KEY}" \
    2>/dev/null || echo "000")

  if [ "$RESEND_STATUS" = "200" ]; then
    check "pass" "Resend API key valid"
  else
    check "fail" "Resend API key invalid (HTTP $RESEND_STATUS)"
  fi
else
  check "warn" "Resend not configured (optional)"
fi

# === SUMMARY ===
echo ""
echo "==========================================="
echo "  SUMMARY"
echo "==========================================="
echo -e "  ${GREEN}Passed:${NC}   $PASSED"
echo -e "  ${RED}Failed:${NC}   $FAILED"
echo -e "  ${YELLOW}Warnings:${NC} $WARNINGS"
echo -e "  Total:    $TOTAL"
echo ""

if [ "$FAILED" -eq 0 ]; then
  echo -e "  ${GREEN}🎉 Stack is fully wired and operational!${NC}"
  exit 0
elif [ "$FAILED" -le 2 ]; then
  echo -e "  ${YELLOW}⚠️  Almost there — fix the failing checks above.${NC}"
  exit 1
else
  echo -e "  ${RED}🚫 Multiple issues detected. Review the report above.${NC}"
  exit 2
fi
