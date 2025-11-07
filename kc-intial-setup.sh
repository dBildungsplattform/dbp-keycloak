#!/bin/bash

# --- Configuration ---
KEYCLOAK_HOST="https://enrichment.dev.dbildungsplattform.de"
ADMIN_USER="admin"
ADMIN_PASS=${ADMIN_PASS}
REALM="Enrichment"


# --- Enable User Event and Admin Event Monitoring Expiration ---
EVENTS_EXPIRATION_SECONDS=2592000 # 30 Tage

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

# --- Check if Realm exists ---
REALM_EXISTS=$(curl -s -X GET "$KEYCLOAK_HOST/auth/admin/realms/$REALM" \
  -H "Authorization: Bearer $KC_ACCESS_TOKEN" \
  -o /dev/null -w "%{http_code}")

if [ "$REALM_EXISTS" == "200" ]; then
  echo "Realm '$REALM' already exists. Skipping creation."
else
  echo "Creating realm '$REALM'..."
  curl -s -X POST "$KEYCLOAK_HOST/auth/admin/realms" \
    -H "Authorization: Bearer $KC_ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{
          \"realm\": \"$REALM\",
          \"displayName\": \"$REALM\",
          \"displayNameHtml\": \"<b>$REALM</b>\",
          \"enabled\": true,
          \"internationalizationEnabled\": true,
          \"supportedLocales\": [\"de\"],
          \"defaultLocale\": \"de\",
          \"resetPasswordAllowed\": true,
          \"loginWithEmailAllowed\": false,
          \"bruteForceProtected\": true,
          \"loginTheme\": \"enrichment\",
          \"emailTheme\": \"enrichment\",
          \"eventsEnabled\": true,
          \"adminEventsEnabled\": true,
          \"ssoSessionIdleTimeout\": 2400,
          \"ssoSessionMaxLifespan\": 28800,
          \"accessTokenLifespan\": 1800,
          \"passwordPolicy\": \"length(8) and digits(1) and upperCase(1) and lowerCase(1) and specialChars(1) and notUsername() and notEmail() \"
        }"
# not working
#          \"attributes\": {
#             \"unmanagedAttributePolicy\": \"Enabled\"
#          }
# 

  echo "Realm '$REALM' created."
fi


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

# --- Create enrichment-backup client with only Direct Access Grants ---
CLIENT_ID="enrichment-backend"
CLIENT_EXISTS=$(curl -s -X GET "$KEYCLOAK_HOST/auth/admin/realms/$REALM/clients?clientId=$CLIENT_ID" \
  -H "Authorization: Bearer $KC_ACCESS_TOKEN" | jq 'length')

if [ "$CLIENT_EXISTS" -gt 0 ]; then
  echo "Client '$CLIENT_ID' already exists in realm '$REALM'. Skipping creation."
else
  echo "Creating client '$CLIENT_ID' in realm '$REALM'..."
  curl -s -X POST "$KEYCLOAK_HOST/auth/admin/realms/$REALM/clients" \
    -H "Authorization: Bearer $KC_ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{
          \"clientId\": \"$CLIENT_ID\",
          \"description\": \"Backend Client für Enrichment\",
          \"enabled\": true,
          \"protocol\": \"openid-connect\",
          \"publicClient\": true,
          \"directAccessGrantsEnabled\": true,
          \"standardFlowEnabled\": false,
          \"serviceAccountsEnabled\": true,
          \"publicClient\": false,
          \"authorizationServicesEnabled\": true,
          \"rootUrl\": \"https://enrichment.staging.dbildungsplattform.de\",
          \"baseUrl\": \"https://enrichment.staging.dbildungsplattform.de\",
          \"redirectUris\": [\"https://enrichment.staging.dbildungsplattform.de/*\"]
        }"
  echo "Client '$CLIENT_ID' created."
fi

# --- Service Account Roles für enrichment-backend hinzufügen ---
# Hole die Client-ID (UUID) für enrichment-backend
BACKEND_CLIENT_UUID=$(curl -s -X GET "$KEYCLOAK_HOST/auth/admin/realms/$REALM/clients?clientId=$CLIENT_ID" \
  -H "Authorization: Bearer $KC_ACCESS_TOKEN" | jq -r '.[0].id')

if [ -z "$BACKEND_CLIENT_UUID" ] || [ "$BACKEND_CLIENT_UUID" == "null" ]; then
  echo "Client-ID für '$CLIENT_ID' nicht gefunden, kann Service Account Rollen nicht zuweisen."
else
  # Hole die Rollen-IDs für view-users, query-users, manage-users
  for ROLE in view-users query-users manage-users; do
    ROLE_ID=$(curl -s -X GET "$KEYCLOAK_HOST/auth/admin/realms/$REALM/roles/$ROLE" \
      -H "Authorization: Bearer $KC_ACCESS_TOKEN" | jq -r '.id')
    if [ -z "$ROLE_ID" ] || [ "$ROLE_ID" == "null" ]; then
      echo "Rolle '$ROLE' nicht gefunden, überspringe."
      continue
    fi

    # Service Account User-ID holen
    SERVICE_ACCOUNT_USER_ID=$(curl -s -X GET "$KEYCLOAK_HOST/auth/admin/realms/$REALM/users?username=service-account-$CLIENT_ID" \
      -H "Authorization: Bearer $KC_ACCESS_TOKEN" | jq -r '.[0].id')
    if [ -z "$SERVICE_ACCOUNT_USER_ID" ] || [ "$SERVICE_ACCOUNT_USER_ID" == "null" ]; then
      echo "Service Account User für '$CLIENT_ID' nicht gefunden, überspringe."
      continue
    fi

    # Rolle zuweisen
    echo "Weise Rolle '$ROLE' dem Service Account von '$CLIENT_ID' zu..."
    curl -s -X POST "$KEYCLOAK_HOST/auth/admin/realms/$REALM/users/$SERVICE_ACCOUNT_USER_ID/role-mappings/realm" \
      -H "Authorization: Bearer $KC_ACCESS_TOKEN" \
      -H "Content-Type: application/json" \
      -d "[{\"id\": \"$ROLE_ID\", \"name\": \"$ROLE\"}]"
  done
fi


CLIENT_ID="enrichment-frontend"
CLIENT_EXISTS=$(curl -s -X GET "$KEYCLOAK_HOST/auth/admin/realms/$REALM/clients?clientId=$CLIENT_ID" \
  -H "Authorization: Bearer $KC_ACCESS_TOKEN" | jq 'length')

if [ "$CLIENT_EXISTS" -gt 0 ]; then
  echo "Client '$CLIENT_ID' already exists in realm '$REALM'. Skipping creation."
else
  echo "Creating client '$CLIENT_ID' in realm '$REALM'..."
  curl -s -X POST "$KEYCLOAK_HOST/auth/admin/realms/$REALM/clients" \
    -H "Authorization: Bearer $KC_ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{
          \"clientId\": \"$CLIENT_ID\",
          \"description\": \"Client für das Frontend von Enrichment\",
          \"enabled\": true,
          \"protocol\": \"openid-connect\",
          \"publicClient\": true,
          \"directAccessGrantsEnabled\": true,
          \"standardFlowEnabled\": true,
          \"rootUrl\": \"https://enrichment.staging.dbildungsplattform.de\",
          \"baseUrl\": \"https://enrichment.staging.dbildungsplattform.de\",
          \"redirectUris\": [\"https://enrichment.staging.dbildungsplattform.de/*\"]
          }"
        echo "Client '$CLIENT_ID' created."
      fi


      # --- Role Configuration ---
      declare -A ROLES
      ROLES=(
        ["enrichment_officer"]="Standardrolle für Enrichment Frontend"
        ["association_director"]="Rolle für Verbandsdirektor"
        ["course_instructor"]="Rolle für Kursleiter"
        ["guest_student"]="Rolle für Gaststudent"
        ["state_coordinator"]="Rolle für Landeskoodinator"
        ["student"]="Rolle für Schüler"
      )

      for ROLE_NAME in "${!ROLES[@]}"; do
        ROLE_DESCRIPTION="${ROLES[$ROLE_NAME]}"

        # --- Check if Role exists ---
        ROLE_EXISTS=$(curl -s -X GET "$KEYCLOAK_HOST/auth/admin/realms/$REALM/roles/$ROLE_NAME" \
        -H "Authorization: Bearer $KC_ACCESS_TOKEN" \
        -o /dev/null -w "%{http_code}")

        if [ "$ROLE_EXISTS" == "200" ]; then
        echo "Role '$ROLE_NAME' already exists in realm '$REALM'. Skipping creation."
        else
        echo "Creating role '$ROLE_NAME' in realm '$REALM'..."
        curl -s -X POST "$KEYCLOAK_HOST/auth/admin/realms/$REALM/roles" \
          -H "Authorization: Bearer $KC_ACCESS_TOKEN" \
          -H "Content-Type: application/json" \
          -d "{
            \"name\": \"$ROLE_NAME\",
            \"description\": \"$ROLE_DESCRIPTION\",
            \"composite\": false,
            \"clientRole\": false,
            \"containerId\": \"$REALM\"
            }"
        echo "Role '$ROLE_NAME' created."
        fi
      done

# --- Neue Client Scopes anlegen ---
declare -A NEW_CLIENT_SCOPES
NEW_CLIENT_SCOPES=(
  ["course_instructor_scope"]="Client Scope für Kursleiter"
  ["association_director_scope"]="Client Scope für Verbandsdirektor"
  ["enrichment_officer_scope"]="Client Scope für Enrichment Officer"
  ["student_scope"]="Client Scope für Schüler"
  ["guest_student_scope"]="Client Scope für Gaststudent"
)

for SCOPE_NAME in "${!NEW_CLIENT_SCOPES[@]}"; do
  SCOPE_DESCRIPTION="${NEW_CLIENT_SCOPES[$SCOPE_NAME]}"
  # Prüfen, ob der Scope existiert
  SCOPE_EXISTS=$(curl -s -X GET "$KEYCLOAK_HOST/auth/admin/realms/$REALM/client-scopes?name=$SCOPE_NAME" \
    -H "Authorization: Bearer $KC_ACCESS_TOKEN" | jq 'length')

  if [ "$SCOPE_EXISTS" == "200" ]; then
    echo "Client Scope '$SCOPE_NAME' existiert bereits. Überspringe Erstellung."
  else
    echo "Erstelle Client Scope '$SCOPE_NAME'..."
    curl -s -X POST "$KEYCLOAK_HOST/auth/admin/realms/$REALM/client-scopes" \
      -H "Authorization: Bearer $KC_ACCESS_TOKEN" \
      -H "Content-Type: application/json" \
      -d "{
        \"name\": \"$SCOPE_NAME\",
        \"description\": \"$SCOPE_DESCRIPTION\",
        \"protocol\": \"openid-connect\",
        \"attributes\": {\"display.on.consent.screen\": \"false\", \"include.in.token.scope\": \"true\"}
        }"
    echo "Client Scope '$SCOPE_NAME' erstellt."
  fi
done

# --- Mapper für Client Scopes hinzufügen (wartungsfreundlich) ---
declare -A SCOPE_MAPPERS
SCOPE_MAPPERS=(
  [course_instructor_scope]="course_instructor_school_id course_instructor_association_id"
  [association_director_scope]="association_director_association_id"
  [enrichment_officer_scope]="enrichment_officer_association_id enrichment_officer_school_id"
  [student_scope]="student_association_id student_school_id class_level"
  [guest_student_scope]="student_association_id guest_student_class_level"
)

for SCOPE_NAME in "${!SCOPE_MAPPERS[@]}"; do
  # Scope-ID abfragen
  SCOPE_ID=$(curl -s -X GET "$KEYCLOAK_HOST/auth/admin/realms/$REALM/client-scopes" \
    -H "Authorization: Bearer $KC_ACCESS_TOKEN" | jq -r ".[] | select(.name==\"$SCOPE_NAME\") | .id")
  if [ -z "$SCOPE_ID" ]; then
    echo "Client Scope '$SCOPE_NAME' nicht gefunden, Mapper werden nicht hinzugefügt."
    continue
  fi
  # --- Mapper hinzufügen ---
  for MAPPER in ${SCOPE_MAPPERS[$SCOPE_NAME]}; do
    echo "Füge Mapper '$MAPPER' zu Scope '$SCOPE_NAME' hinzu..."
    curl -s -X POST "$KEYCLOAK_HOST/auth/admin/realms/$REALM/client-scopes/$SCOPE_ID/protocol-mappers/models" \
      -H "Authorization: Bearer $KC_ACCESS_TOKEN" \
      -H "Content-Type: application/json" \
      -d "{
        \"name\": \"$MAPPER\",
        \"protocol\": \"openid-connect\",
        \"protocolMapper\": \"oidc-usermodel-attribute-mapper\",
        \"consentRequired\": false,
        \"config\": {
          \"access.token.claim\": \"true\",
          \"id.token.claim\": \"true\",
          \"introspection.token.claim\": \"true\",
          \"userinfo.token.claim\": \"true\",
          \"user.attribute\": \"$MAPPER\",
          \"claim.name\": \"$MAPPER\",
          \"jsonType.label\": \"String\",
          \"multivalued\": \"true\"
        }
      }"
  done

  # --- Rolle zum Client Scope hinzufügen ---
  # Beispiel: Rolle "course_instructor" zum Scope "course_instructor_scope" zuweisen
  # Nur ausführen, wenn Scope und Rolle existieren
  ROLE_NAME="${SCOPE_NAME/_scope/}" # z.B. "course_instructor_scope" -> "course_instructor"
  ROLE_ID=$(curl -s -X GET "$KEYCLOAK_HOST/auth/admin/realms/$REALM/roles/$ROLE_NAME" \
    -H "Authorization: Bearer $KC_ACCESS_TOKEN" | jq -r '.id')

  if [ -n "$ROLE_ID" ] && [ "$ROLE_ID" != "null" ]; then
    echo "Füge Rolle '$ROLE_NAME' zu Scope '$SCOPE_NAME' hinzu..."
    curl -s -X POST "$KEYCLOAK_HOST/auth/admin/realms/$REALM/client-scopes/$SCOPE_ID/scope-mappings/realm" \
      -H "Authorization: Bearer $KC_ACCESS_TOKEN" \
      -H "Content-Type: application/json" \
      -d "[{\"id\": \"$ROLE_ID\", \"name\": \"$ROLE_NAME\"}]"
    echo "Rolle '$ROLE_NAME' wurde Scope '$SCOPE_NAME' zugewiesen."
  else
    echo "Rolle '$ROLE_NAME' nicht gefunden, kann nicht zu Scope '$SCOPE_NAME' zugewiesen werden."
  fi
  done
  echo "Alle Mapper für Scope '$SCOPE_NAME' hinzugefügt."
