#!/usr/bin/env bash
set -euo pipefail

echo "[firebase-bootstrap] starting..."
command -v firebase >/dev/null 2>&1 || { echo "Firebase CLI is required. Install via npm i -g firebase-tools"; exit 1; }

PROJECT_ID="${1:-}" 
if [[ -z "$PROJECT_ID" ]]; then
  echo "[firebase-bootstrap] No project id provided. Listing projects (requires firebase login)..."
  firebase projects:list || true
  read -rp "Enter Firebase project id to use (or create in console then re-run): " PROJECT_ID
fi

if [[ -z "$PROJECT_ID" ]]; then
  echo "[firebase-bootstrap] Project id still empty; exiting." >&2
  exit 1
fi

cat > firebase.json <<'JSON'
{
  "flutter": {
    "platforms": {
      "android": {
        "default": {
          "projectId": "__PROJECT_ID__",
          "appId": "CHANGE_WITH_flutterfire_configure",
          "fileOutput": "android/app/google-services.json"
        }
      },
      "dart": {
        "lib/firebase_options.dart": {
          "projectId": "__PROJECT_ID__",
          "configurations": {
            "android": "CHANGE_WITH_flutterfire_configure",
            "ios": "CHANGE_WITH_flutterfire_configure",
            "macos": "CHANGE_WITH_flutterfire_configure",
            "web": "CHANGE_WITH_flutterfire_configure",
            "windows": "CHANGE_WITH_flutterfire_configure"
          }
        }
      }
    }
  },
  "firestore": {
    "rules": "firestore.rules",
    "indexes": "firestore.indexes.json"
  },
  "storage": {
    "rules": "storage.rules"
  },
  "database": {
    "rules": "database.rules.json"
  },
  "emulators": {
    "auth": { "port": 9099 },
    "firestore": { "port": 8080 },
    "storage": { "port": 9199 },
    "database": { "port": 9000 },
    "ui": { "enabled": true, "port": 4400 }
  }
}
JSON
sed -i "s/__PROJECT_ID__/$PROJECT_ID/g" firebase.json

cat > firestore.rules <<'RULES'
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /community_posts/{docId} {
      allow read, write: if request.time < timestamp.date(3020, 1, 1);
    }
    match /community_posts_test/{docId} {
      allow read, write: if true; // emulator-friendly sandbox
    }
  }
}
RULES

cat > firestore.indexes.json <<'IDX'
{
  "indexes": [
    {
      "collectionGroup": "community_posts",
      "queryScope": "COLLECTION",
      "fields": [
        {"fieldPath": "created_at", "order": "DESCENDING"}
      ]
    },
    {
      "collectionGroup": "community_posts_test",
      "queryScope": "COLLECTION",
      "fields": [
        {"fieldPath": "created_at", "order": "DESCENDING"}
      ]
    }
  ],
  "fieldOverrides": []
}
IDX

cat > storage.rules <<'SRULES'
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    match /{allPaths=**} {
      allow read, write: if true; // emulator friendly; tighten for prod
    }
  }
}
SRULES

cat > database.rules.json <<'DBRULES'
{
  "rules": {
    ".read": true,
    ".write": true
  }
}
DBRULES

cat > .firebaserc <<RC
{
  "projects": {
    "default": "$PROJECT_ID"
  }
}
RC

echo "[firebase-bootstrap] using project $PROJECT_ID"
firebase use "$PROJECT_ID" --add

if command -v flutterfire >/dev/null 2>&1; then
  echo "[firebase-bootstrap] Detected flutterfire CLI; attempting to generate firebase_options.dart for $PROJECT_ID"
  flutterfire configure --project="$PROJECT_ID" --yes --out=lib/firebase_options.dart --platforms=android,ios,macos,web,windows || echo "[firebase-bootstrap] flutterfire configure did not complete; existing firebase_options.dart will be used."
else
  echo "[firebase-bootstrap] flutterfire CLI not found. Skipping firebase_options.dart regeneration (existing file left intact)."
fi

echo "[firebase-bootstrap] deploying rules + indexes"
firebase deploy --only firestore:rules,firestore:indexes,storage,database || true

echo "[firebase-bootstrap] bootstrap finished. Run 'firebase emulators:start' to test locally."
