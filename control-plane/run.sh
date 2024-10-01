#!/bin/bash -e

set -e
set -o pipefail

KUBE_BURNER_VERSION=1.3.3
KUBE_DIR=${KUBE_DIR:-/tmp}
KUBE_BURNER_URL="https://github.com/kube-burner/kube-burner-ocp/releases/download/v${KUBE_BURNER_VERSION}/kube-burner-ocp-V${KUBE_BURNER_VERSION}-linux-x86_64.tar.gz"
PROMETHEUS_HOST=https://$(oc get route -n openshift-monitoring prometheus-k8s -o go-template="{{.spec.host}}")
PROMETHEUS_ISTIO_HOST=https://$(oc get route -n istio-system prometheus -o go-template="{{.spec.host}}")
PROMETHEUS_ISTIO_PASSWORD=$(oc get secret/htpasswd -n istio-system -o go-template="{{.data.rawPassword|base64decode}}")
ES_INDEX=${ES_INDEX:-kube-burner}
ES_SERVER=${ES_SERVER:-http://es-instance.com:9200}
TOKEN=$(oc sa new-token -n openshift-monitoring prometheus-k8s)
WORKLOAD=${WORKLOAD:?}
EXTRA_FLAGS=${EXTRA_FLAGS:-}
PODS_PER_NODE=${PODS_PER_NODE:-220}
WORKER_COUNT=$(oc get node -l node-role.kubernetes.io/worker,node-role.kubernetes.io/master!=,node-role.kubernetes.io/infra!= --no-headers | wc -l)
JOB_ITERATIONS=$((WORKER_COUNT * 9))
INGRESS_DOMAIN=$(oc get ingresscontroller -n openshift-ingress-operator default -o jsonpath="{.status.domain}")

export PROMETHEUS_HOST PROMETHEUS_ISTIO_HOST PROMETHEUS_ISTIO_PASSWORD PROMETHEUS_PASSWORD TOKEN INGRESS_DOMAIN JOB_ITERATIONS ES_SERVER ES_INDEX

if [[ ! -f /tmp/kube-burner-ocp ]]; then
   curl --fail --retry 8 --retry-all-errors -sS -L "${KUBE_BURNER_URL}" | tar -xzC "${KUBE_DIR}/" kube-burner-ocp
fi

if [[ ${WORKLOAD} == "node-density-sm" ]]; then
  cmd="${KUBE_DIR}/kube-burner-ocp node-density --pods-per-node=${PODS_PER_NODE}"
else
  cmd="${KUBE_DIR}/kube-burner-ocp init -c ${WORKLOAD}.yml"
fi
cd ${WORKLOAD}

# If ES_SERVER is specified
if [[ -n ${ES_SERVER} ]]; then
  cmd+=" --metrics-endpoint=metrics-endpoint.yml"
fi
cmd+=" ${EXTRA_FLAGS}"

echo ${cmd}
${cmd}
exit $?
