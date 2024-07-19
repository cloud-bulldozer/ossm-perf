#!/bin/bash

git clone https://github.com/kiali/kiali.git
cd kiali
npm install cypress --save-dev
yarn add cypress --dev
cd frontend
npm install cypress --save-dev
yarn add cypress --dev
cd ..

KIALI_ROUTE=$(oc get route kiali -n ${SMCP_NAMESPACE} -o=jsonpath='{.spec.host}')
export CYPRESS_BASE_URL="https://${KIALI_ROUTE}"
export CYPRESS_USERNAME=${OCP_CRED_USR}
export CYPRESS_PASSWD=${OCP_CRED_PSW}
export CYPRESS_AUTH_PROVIDER="kube:admin"


chmod +x hack/run-performance-tests.sh

./hack/run-performance-tests.sh
