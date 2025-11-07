#!/bin/bash

# --- Configuration ---
KEYCLOAK_HOST="https://enrichment.dev.dbildungsplattform.de"
ADMIN_USER="admin"
ADMIN_PASS=${ADMIN_PASS}
REALM="master"

# --- Get Access Token ---
KC_ACCESS_TOKEN=$(curl -s -X POST "$KEYCLOAK_HOST/auth/realms/master/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=$ADMIN_USER" \
  -d "password=$ADMIN_PASS" \
  -d "grant_type=password" \
  -d "client_id=admin-cli" | jq -r .access_token)

if [ -z "$KC_ACCESS_TOKEN" ] || [ "$KC_ACCESS_TOKEN" == "null" ]; then
  echo "Failed to retrieve access token."
  exit 1
fi

# --- Update Realm Settings ---
echo "Updating realm '$REALM'..."
curl -s -X PUT "$KEYCLOAK_HOST/auth/admin/realms/$REALM" \
  -H "Authorization: Bearer $KC_ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
        \"bruteForceProtected\": true,
        \"eventsEnabled\": true,
        \"adminEventsEnabled\": true,
        \"ssoSessionIdleTimeout\": 2400,
        \"ssoSessionMaxLifespan\": 28800,
        \"accessTokenLifespan\": 1800,
        \"passwordPolicy\": \"length(16) and digits(1) and upperCase(1) and lowerCase(1) and specialChars(1) and notUsername() and notEmail() \"
      }"
echo "Realm '$REALM' updated."


# --- SMTP Konfiguration für den Master Realm ---
SMTP_HOST="mailpit.enrichment.svc.cluster.local"
SMTP_PORT="1025"
SMTP_FROM="noreply@enrichment.schleswig-holstein.de"
SMTP_AUTH="true"
SMTP_USER="user"
SMTP_PASS="smtp-password"
SMTP_STARTTLS="true"

echo "Konfiguriere SMTP für den $REALM Realm..."

curl -s -X PUT "$KEYCLOAK_HOST/auth/admin/realms/$REALM" \
  -H "Authorization: Bearer $KC_ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"smtpServer\": {
      \"host\": \"$SMTP_HOST\",
      \"port\": \"$SMTP_PORT\",
      \"from\": \"$SMTP_FROM\",
      \"auth\": \"$SMTP_AUTH\",
      \"user\": \"$SMTP_USER\",
      \"password\": \"$SMTP_PASS\",
      \"starttls\": \"$SMTP_STARTTLS\"
    }
  }"

echo "SMTP Konfiguration für den $REALM Realm abgeschlossen."

# --- Enable User Event and Admin Event Monitoring ---
EVENTS_EXPIRATION_SECONDS=2592000 # 30 Tage

# --- Enable User Event and Admin Event Monitoring ---
echo "Aktiviere User Event und Admin Event Monitoring für Realm '$REALM'..."

curl -s -X PUT "$KEYCLOAK_HOST/auth/admin/realms/$REALM" \
  -H "Authorization: Bearer $KC_ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"eventsEnabled\": true,
    \"eventsListeners\": [\"jboss-logging\"],
    \"adminEventsEnabled\": true,
    \"adminEventsDetailsEnabled\": true,
    \"eventsExpiration\": $EVENTS_EXPIRATION_SECONDS
  }"

echo "User Event und Admin Event Monitoring für Realm '$REALM' aktiviert."

# --- Brute-Force Detection konfigurieren ---
BRUTE_FORCE_ENABLED=true
MAX_FAILURES=5
WAIT_INCREMENT_SECONDS=60
QUICK_LOGIN_CHECK_MILLISECONDS=1000
MINIMUM_QUICK_LOGIN_WAIT_SECONDS=60
MAX_WAIT_SECONDS=900
FAILURE_RESET_TIME_SECONDS=43200

echo "Konfiguriere Brute-Force-Detection für Realm '$REALM'..."
curl -s -X PUT "$KEYCLOAK_HOST/auth/admin/realms/$REALM" \
  -H "Authorization: Bearer $KC_ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"bruteForceProtected\": $BRUTE_FORCE_ENABLED,
    \"maxFailureWaitSeconds\": $MAX_WAIT_SECONDS,
    \"minimumQuickLoginWaitSeconds\": $MINIMUM_QUICK_LOGIN_WAIT_SECONDS,
    \"waitIncrementSeconds\": $WAIT_INCREMENT_SECONDS,
    \"quickLoginCheckMilliSeconds\": $QUICK_LOGIN_CHECK_MILLISECONDS,
    \"maxDeltaTimeSeconds\": $FAILURE_RESET_TIME_SECONDS,
    \"failureFactor\": $MAX_FAILURES
  }"
echo "Brute-Force-Detection für Realm '$REALM' konfiguriert."

echo "Initiale Keycloak Konfiguration abgeschlossen."
