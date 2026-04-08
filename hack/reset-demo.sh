#!/bin/sh

set -ex

required_vars="
  ARGOCD_SERVER
  ARGOCD_AUTH_TOKEN
  AKUITY_ORG_ID
  KARGO_API_TOKEN
  KARGO_API_ADDRESS
"
for var in $required_vars; do
  eval val=\$$var
  if [ -z "$val" ]; then
    echo "Error: required environment variable $var is not set" >&2
    exit 1
  fi
done

# Needed to prevent argocd from trying to read the default config file
ARGOCD_CONFIG=$(mktemp)
cat > "${ARGOCD_CONFIG}" << EOF
contexts:
- name: default
  server: ${ARGOCD_SERVER}
  user: default
current-context: default
servers:
- grpc-web: true
  server: ${ARGOCD_SERVER}
users:
- auth-token: ${ARGOCD_AUTH_TOKEN}
  name: default
EOF
chmod 0600 "${ARGOCD_CONFIG}"
trap 'rm -f "${ARGOCD_CONFIG}"' EXIT

# Reset Argo CD
if ! command -v argocd &>/dev/null; then
  curl -sSL -o /usr/local/bin/argocd https://${ARGOCD_SERVER}/download/argocd-linux-amd64
  chmod +x /usr/local/bin/argocd
fi
argocd --config="${ARGOCD_CONFIG}" app delete-resource guestbook-prod-oom --kind Deployment --resource-name oom-demo || true
argocd --config="${ARGOCD_CONFIG}" app delete-resource akp-demo-bootstrap-kargo --kind Stage --resource-name prod-oom || true
for i in $(seq 1 5); do
  argocd --config="${ARGOCD_CONFIG}" app sync akp-demo-bootstrap-kargo && break
  echo "Sync attempt $i failed, retrying in 8s..."
  sleep 8
done
argocd --config="${ARGOCD_CONFIG}" proj create -f ./pipeline-demo/argocd/00-project.yaml --upsert
argocd --config="${ARGOCD_CONFIG}" app create -f ./pipeline-demo/argocd/01-argocd-apps.yaml --upsert

# Delete AI conversations
BASE_URL="https://${ARGOCD_SERVER}/ext-api/v1/argocd/extensions/kubevision/orgs/${AKUITY_ORG_ID}/ai/conversations"
INSTANCE_ID="${ARGOCD_SERVER#https://}"
INSTANCE_ID="${INSTANCE_ID%%.*}"

{ set +x; } 2>/dev/null
CONVERSATION_IDS=$(curl -sSL "${BASE_URL}?instanceId=${INSTANCE_ID}&limit=50" \
    -b "argocd.token=${ARGOCD_AUTH_TOKEN}" \
    -H 'x-platform: argocd' | jq -r '.conversations[].id')

echo "Deleting conversations: ${CONVERSATION_IDS}"
for id in $CONVERSATION_IDS; do
  curl -sSL -X DELETE "${BASE_URL}/${id}?instanceId=${INSTANCE_ID}" \
    -b "argocd.token=${ARGOCD_AUTH_TOKEN}" \
    -H 'x-platform: argocd'
done
set -x

# Reset Kargo
if ! command -v kargo &>/dev/null; then
  curl -L -o /usr/local/bin/kargo https://github.com/akuity/kargo/releases/download/v1.10.8/kargo-linux-amd64
  chmod +x /usr/local/bin/kargo
fi
kargo delete stage --project pipeline-demo dev staging prod-eu prod-us || true
kargo apply -R -f ./pipeline-demo/kargo
sleep 4
kargo promote --project=pipeline-demo --freight-alias=kindled-turtle --stage=dev
