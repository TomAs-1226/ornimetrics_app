#!/usr/bin/env bash
# Deploy Firebase security rules for the Ornimetrics app.
#
# Why you need this: the app's "permission denied" errors (Realtime Database
# "Error fetching fresh data", and account photos not loading from Storage)
# mean the *deployed* rules are stricter than the rules files in this repo
# (storage.rules / database.rules.json / firestore.rules are all permissive).
# Deploying them makes reads/writes work for signed-in users.
#
# One-time setup:
#   npm install -g firebase-tools     # or: brew install firebase-cli
#   firebase login
#
# Then run:
#   bash scripts/deploy_firebase_rules.sh
set -euo pipefail

if ! command -v firebase >/dev/null 2>&1; then
  echo "firebase CLI not found. Install it first:"
  echo "  npm install -g firebase-tools   (then: firebase login)"
  exit 1
fi

PROJECT="ornimetrics"
echo "Deploying Firestore, Storage and Realtime Database rules to '$PROJECT'…"
firebase deploy --project "$PROJECT" \
  --only firestore:rules,storage,database

echo "Done. Re-launch the app; the permission-denied errors should be gone."
