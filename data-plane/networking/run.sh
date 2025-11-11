NETPERF_VERSION=0.1.34
MESH_MODE=${MESH_MODE}
WAYPOINT=${WAYPOINT}
OS=$(uname -s)
HARDWARE=$(uname -m)
curl -sSL https://github.com/cloud-bulldozer/k8s-netperf/releases/download/v${NETPERF_VERSION}/k8s-netperf_${OS}_v${NETPERF_VERSION}_${HARDWARE}.tar.gz | tar xzf - k8s-netperf
oc create ns netperf 2>/dev/null
if [[ ${MESH_MODE} == "sidecar" ]]; then
  echo "Adding istio-injection=enabled label to ns"
  oc label ns netperf istio-injection=enabled --overwrite
elif [[ ${MESH_MODE} == "ambient" ]]; then
  echo "Adding istio.io/dataplane-mode=ambient label to ns"
  oc label ns netperf istio.io/dataplane-mode=ambient --overwrite
  if [[ ${WAYPOINT} == "true" ]]; then
  oc apply -f waypoint.yml
  echo "Adding istio.io/use-waypoint=waypoint label to ns"
  oc label ns netperf istio.io/use-waypoint=waypoint --overwrite
  fi
else
  echo "No known MESH_MODE defined (sidecar, ambient). Running with default CNI"
fi
oc create sa netperf -n netperf
oc adm policy add-scc-to-user hostnetwork -z netperf -n netperf
if [[ $2 != "" ]]; then
 cmd="./k8s-netperf --all --config ${1} --search ${2} --clean=false --csv=false"
else
  cmd="./k8s-netperf --all --config ${1} --clean=false --csv=false"
fi
echo ${cmd}
${cmd}
oc delete ns netperf
