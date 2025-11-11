#!/bin/bash

set -e

echo "============================================="
echo "Moving OpenShift components to infra nodes"
echo "============================================="
echo

# Check if oc is available
if ! command -v oc &> /dev/null; then
    echo "ERROR: oc command not found. Please ensure OpenShift CLI is installed and in PATH."
    exit 1
fi

# Check if logged in to OpenShift
if ! oc whoami &> /dev/null; then
    echo "ERROR: Not logged in to OpenShift. Please login using 'oc login' first."
    exit 1
fi

echo "Step 1/3: Moving ingress to infra nodes..."
echo "----------------------------------------"
oc patch -n openshift-ingress-operator ingresscontrollers.operator.openshift.io default -p '{"spec": {"nodePlacement": {"nodeSelector": {"matchLabels": {"node-role.kubernetes.io/infra": ""}}, "tolerations": [{"effect": "NoSchedule", "key": "node-role.kubernetes.io/infra", "operator": "Exists"}]}}}' --type merge

echo "Waiting for ingress rollout to complete..."
oc rollout status deployment router-default -n openshift-ingress
echo "✅ Ingress moved to infra nodes successfully"
echo

echo "Step 2/3: Moving image registry to infra nodes..."
echo "------------------------------------------------"
oc apply -f - <<EOF
apiVersion: imageregistry.operator.openshift.io/v1
kind: Config 
metadata:
  name: cluster
spec:
  affinity:
    podAntiAffinity:
      preferredDuringSchedulingIgnoredDuringExecution:
      - podAffinityTerm:
          namespaces:
          - openshift-image-registry
          topologyKey: kubernetes.io/hostname
        weight: 100
  nodeSelector:
    node-role.kubernetes.io/infra: ""
  tolerations:
  - effect: NoSchedule
    key: node-role.kubernetes.io/infra
    operator: Exists
  - effect: NoExecute
    key: node-role.kubernetes.io/infra
    operator: Exists 
EOF

echo "Waiting for image registry rollout to complete..."
oc rollout status deployment image-registry -n openshift-image-registry
echo "✅ Image registry moved to infra nodes successfully"
echo

echo "Step 3/3: Moving monitoring components to infra nodes..."
echo "------------------------------------------------------"
oc apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: cluster-monitoring-config
  namespace: openshift-monitoring
data:
  config.yaml: |+
    alertmanagerMain:
      nodeSelector: 
        node-role.kubernetes.io/infra: ""
      tolerations:
      - key: node-role.kubernetes.io/infra
        operator: Exists
        effect: NoSchedule
      - key: node-role.kubernetes.io/infra
        operator: Exists
        effect: NoExecute
    prometheusK8s:
      retention: 15d
      nodeSelector:
        node-role.kubernetes.io/infra: ""
      tolerations:
      - key: node-role.kubernetes.io/infra
        operator: Exists
        effect: NoSchedule
      - key: node-role.kubernetes.io/infra
        operator: Exists
        effect: NoExecute
    prometheusOperator:
      nodeSelector:
        node-role.kubernetes.io/infra: ""
      tolerations:
      - key: node-role.kubernetes.io/infra
        operator: Exists
        effect: NoSchedule
      - key: node-role.kubernetes.io/infra
        operator: Exists
        effect: NoExecute
    metricsServer:
      nodeSelector:
        node-role.kubernetes.io/infra: ""
      tolerations:
      - key: node-role.kubernetes.io/infra
        operator: Exists
        effect: NoSchedule
      - key: node-role.kubernetes.io/infra
        operator: Exists
        effect: NoExecute
    k8sPrometheusAdapter:
      nodeSelector:
        node-role.kubernetes.io/infra: ""
      tolerations:
      - key: node-role.kubernetes.io/infra
        operator: Exists
        effect: NoSchedule
      - key: node-role.kubernetes.io/infra
        operator: Exists
        effect: NoExecute
    kubeStateMetrics:
      nodeSelector:
        node-role.kubernetes.io/infra: ""
      tolerations:
      - key: node-role.kubernetes.io/infra
        operator: Exists
        effect: NoSchedule
      - key: node-role.kubernetes.io/infra
        operator: Exists
        effect: NoExecute
    telemeterClient:
      nodeSelector:
        node-role.kubernetes.io/infra: ""
      tolerations:
      - key: node-role.kubernetes.io/infra
        operator: Exists
        effect: NoSchedule
      - key: node-role.kubernetes.io/infra
        operator: Exists
        effect: NoExecute
    openshiftStateMetrics:
      nodeSelector:
        node-role.kubernetes.io/infra: ""
      tolerations:
      - key: node-role.kubernetes.io/infra
        operator: Exists
        effect: NoSchedule
      - key: node-role.kubernetes.io/infra
        operator: Exists
        effect: NoExecute
    thanosQuerier:
      nodeSelector:
        node-role.kubernetes.io/infra: ""
      tolerations:
      - key: node-role.kubernetes.io/infra
        operator: Exists
        effect: NoSchedule
      - key: node-role.kubernetes.io/infra
        operator: Exists
        effect: NoExecute
EOF

echo "✅ Monitoring components configuration applied successfully"
echo

echo "============================================="
echo "Infrastructure components moved to infra nodes successfully"
echo "============================================="
echo
echo "⚠️ Note: Monitoring components may take a few minutes to restart and move to the infra nodes"
