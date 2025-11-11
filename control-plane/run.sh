#!/bin/bash -e

set -e
set -o pipefail

KUBE_BURNER_VERSION=1.7.5
KUBE_DIR=${KUBE_DIR:-/tmp}
OS=$(uname -s)
HARDWARE=$(uname -m)
KUBE_BURNER_URL="https://github.com/kube-burner/kube-burner-ocp/releases/download/v${KUBE_BURNER_VERSION}/kube-burner-ocp-V${KUBE_BURNER_VERSION}-${OS}-${HARDWARE}.tar.gz"
PROMETHEUS_HOST=https://$(oc get route -n openshift-monitoring prometheus-k8s -o go-template="{{.spec.host}}")
ES_INDEX=${ES_INDEX:-kube-burner}
ES_SERVER=${ES_SERVER:-http://es-instance.com:9200}
TOKEN=$(oc create token -n openshift-monitoring prometheus-k8s)
WORKLOAD=${WORKLOAD:?}
EXTRA_FLAGS=${EXTRA_FLAGS:-}
PODS_PER_NODE=${PODS_PER_NODE:-220}
WORKER_COUNT=$(oc get node -l node-role.kubernetes.io/worker,node-role.kubernetes.io/master!=,node-role.kubernetes.io/infra!= --no-headers | wc -l)
JOB_ITERATIONS=$((WORKER_COUNT * 9))
INGRESS_DOMAIN=$(oc get ingresscontroller -n openshift-ingress-operator default -o jsonpath="{.status.domain}")
MESH_MODE=${MESH_MODE}
WAYPOINT=${WAYPOINT}

if [[ ! -f /tmp/kube-burner-ocp ]]; then
   curl --fail --retry 8 --retry-all-errors -sS -L "${KUBE_BURNER_URL}" | tar -xzC "${KUBE_DIR}/" kube-burner-ocp
fi

if [[ ${WORKLOAD} == "node-density-sm" ]]; then
  PODS_RUNNING=$(oc get nodes -l 'node-role.kubernetes.io/worker,node-role.kubernetes.io/infra!=,node-role.kubernetes.io/workload!=' -o custom-columns=NAME:.metadata.name --no-headers | while read node; do oc get pods -A --field-selector=status.phase=Running,spec.nodeName=${node} --no-headers; done | wc -l)
  echo "Currently running pods: ${PODS_RUNNING}"
  JOB_ITERATIONS=$(( WORKER_COUNT * PODS_PER_NODE - PODS_RUNNING))
  echo "Calculated job iterations for node-denisty-sm: ${JOB_ITERATIONS}"
fi

export PROMETHEUS_HOST TOKEN INGRESS_DOMAIN JOB_ITERATIONS ES_SERVER ES_INDEX MESH_MODE WAYPOINT

cmd="${KUBE_DIR}/kube-burner-ocp init -c ${WORKLOAD}.yml"
cd ${WORKLOAD}

# If ES_SERVER is specified
if [[ -n ${ES_SERVER} ]]; then
  cmd+=" --metrics-endpoint=metrics-endpoint.yml"
fi
cmd+=" ${EXTRA_FLAGS}"

echo ${cmd}
${cmd}
exit $?
