#!/usr/bin/env bash
set -euo pipefail

# ./generate-kubeconfig.sh [NAMESPACE] [SERVICEACCOUNT] [OUT_FILE] [DURATION]
NS="${1:-disease-detector}"
SA="${2:-jenkins-service-account}"
OUT="${3:-jenkins-kubeconfig.yaml}"
DURATION="${4:-24h}"     # token duration for TokenRequest API
TIMEOUT_SECS=30

die(){ echo "ERROR: $*" >&2; exit 1; }

# prerequisites
command -v kubectl >/dev/null 2>&1 || die "kubectl not found in PATH"
echo "Current kubectl context: $(kubectl config current-context 2>/dev/null || echo 'unknown')"

# ensure namespace & SA exist
kubectl get ns "${NS}" >/dev/null 2>&1 || die "namespace '${NS}' not found"
kubectl -n "${NS}" get sa "${SA}" >/dev/null 2>&1 || die "serviceaccount '${SA}' not found in ${NS}"

# read cluster server + CA from the kubeconfig kubectl currently uses
CLUSTER_URL=$(kubectl config view --raw -o jsonpath='{.clusters[0].cluster.server}' 2>/dev/null || echo "")
CA_B64=$(kubectl config view --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' 2>/dev/null || echo "")

[ -n "${CLUSTER_URL}" ] || die "cannot determine cluster server URL from kubectl config"

write_kubeconfig() {
  local token="$1"
  cat > "${OUT}" <<EOF
apiVersion: v1
kind: Config
clusters:
- name: cluster-from-current-context
  cluster:
EOF

  if [ -n "${CA_B64}" ]; then
    cat >> "${OUT}" <<EOF
    server: ${CLUSTER_URL}
    certificate-authority-data: ${CA_B64}
EOF
  else
    cat >> "${OUT}" <<EOF
    server: ${CLUSTER_URL}
    insecure-skip-tls-verify: true
EOF
  fi

  cat >> "${OUT}" <<EOF
contexts:
- name: ${SA}-context
  context:
    cluster: cluster-from-current-context
    user: ${SA}-user
    namespace: ${NS}
current-context: ${SA}-context
users:
- name: ${SA}-user
  user:
    token: ${token}
EOF

  # Normalize line endings (best-effort)
  if command -v expand >/dev/null 2>&1; then expand -t 2 "${OUT}" > "${OUT}.tmp" && mv "${OUT}.tmp" "${OUT}" || true; fi
  if sed --version >/dev/null 2>&1; then sed -i 's/\r$//' "${OUT}" 2>/dev/null || true; else sed -i '' -e 's/\r$//' "${OUT}" 2>/dev/null || true; fi

  echo "Wrote kubeconfig: ${OUT}"
  echo "Test with: kubectl --kubeconfig=${OUT} get ns"
}

# Try token via TokenRequest (kubectl create token)
echo "Trying: kubectl create token ${SA} -n ${NS} --duration=${DURATION}"
if kubectl create token --help >/dev/null 2>&1; then
  if TOKEN_RAW=$(kubectl create token "${SA}" -n "${NS}" --duration="${DURATION}" 2>/dev/null || true); then
    if [ -n "${TOKEN_RAW}" ]; then
      TOKEN="$(echo "${TOKEN_RAW}" | tr -d '\n')"
      write_kubeconfig "${TOKEN}"
      exit 0
    fi
  fi
  echo "kubectl create token returned no token or failed; falling back..."
else
  echo "kubectl create token not available; using fallback."
fi

# Fallback: create temporary Secret of type kubernetes.io/service-account-token
TMP_SECRET="${SA}-token-temp-$(date +%s)"
TMP_MANIFEST="$(mktemp -t ${TMP_SECRET}.yaml)"
cat > "${TMP_MANIFEST}" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: ${TMP_SECRET}
  namespace: ${NS}
  annotations:
    kubernetes.io/service-account.name: "${SA}"
type: kubernetes.io/service-account-token
EOF

kubectl apply -f "${TMP_MANIFEST}" >/dev/null
rm -f "${TMP_MANIFEST}"

echo "Waiting up to ${TIMEOUT_SECS}s for token to appear in Secret ${TMP_SECRET}..."
SECS=0
TOKEN=""
while [ "${SECS}" -lt "${TIMEOUT_SECS}" ]; do
  if kubectl get secret "${TMP_SECRET}" -n "${NS}" >/dev/null 2>&1; then
    TOKEN_B64=$(kubectl -n "${NS}" get secret "${TMP_SECRET}" -o jsonpath='{.data.token}' 2>/dev/null || echo "")
    if [ -n "${TOKEN_B64}" ]; then
      TOKEN="$(echo "${TOKEN_B64}" | base64 --decode | tr -d '\n')"
      break
    fi
  fi
  sleep 1
  SECS=$((SECS + 1))
done

[ -n "${TOKEN}" ] || { echo "Secret token not created; inspect: kubectl -n ${NS} get secret ${TMP_SECRET} -o yaml"; exit 1; }

write_kubeconfig "${TOKEN}"
echo ""
echo "Temporary Secret created: ${TMP_SECRET} (delete it when done):"
echo "  kubectl -n ${NS} delete secret ${TMP_SECRET} || true"
echo "If kubectl with generated kubeconfig returns 'Forbidden', bind roles to the ServiceAccount."
exit 0