NETPERF_VERSION=0.1.24
SIDECAR=${SIDECAR:?}
curl -sSL https://github.com/cloud-bulldozer/k8s-netperf/releases/download/v${NETPERF_VERSION}/k8s-netperf_Linux_v${NETPERF_VERSION}_x86_64.tar.gz | tar xzf - k8s-netperf
oc create ns netperf 2>/dev/null
if [[ ${SIDECAR} == "true" ]]; then
  echo "Adding istio-injection=enabled label to ns"
  oc label ns netperf istio-injection=enabled --overwrite
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
