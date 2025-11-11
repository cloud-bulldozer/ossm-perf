#!/bin/bash

# Script to generate OpenShift MachineSet YAML for infrastructure nodes on AWS
#
# Usage:
#   ./infraset-generator-aws.sh                    # Normal mode with auto-detection
#   OC_SKIP_AUTODETECT=1 ./infraset-generator-aws.sh  # Skip auto-detection
#

set -e


# Function to check if we can connect to OpenShift cluster
check_oc_connectivity() {
    # Quick connectivity check with 3-second timeout
    ( oc whoami >/dev/null 2>&1 ) &
    local pid=$!
    sleep 3
    if kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null
        return 1  # Still running, probably hanging
    fi
    wait "$pid" 2>/dev/null
    return $?
}

# Function to auto-detect cluster name
auto_detect_cluster_name() {
    local cluster_name=""
    
    # Check if oc command is available
    if ! command -v oc >/dev/null 2>&1; then
        return 1
    fi
    
    # Check connectivity before trying cluster queries
    if ! check_oc_connectivity; then
        return 1
    fi
    
    # Use OpenShift infrastructure object to get cluster name
    if cluster_name=$(oc get infrastructure cluster -o jsonpath='{.status.infrastructureName}' 2>/dev/null) && [[ -n "$cluster_name" ]]; then
        echo "$cluster_name"
        return 0
    fi
    
    return 1
}

# Function to auto-detect AWS region
auto_detect_aws_region() {
    local region=""
    
    # Check if oc command is available
    if ! command -v oc >/dev/null 2>&1; then
        return 1
    fi
    
    # Check connectivity before trying cluster queries
    if ! check_oc_connectivity; then
        return 1
    fi
    
    # Use OpenShift infrastructure object to get AWS region
    if region=$(oc get infrastructure cluster -o jsonpath='{.status.platformStatus.aws.region}' 2>/dev/null) && [[ -n "$region" ]]; then
        echo "$region"
        return 0
    fi
    
    return 1
}

# Function to auto-detect AMI ID from existing worker machine sets
auto_detect_ami_id() {
    local ami_id=""
       
    # Try to get AMI ID from existing worker machine sets
    if ami_id=$(oc get machinesets -n openshift-machine-api -o jsonpath='{.items[?(@.spec.template.spec.providerSpec.value.instanceType)].spec.template.spec.providerSpec.value.ami.id}' 2>/dev/null | tr ' ' '\n' | head -n1) && [[ -n "$ami_id" ]]; then
        echo "$ami_id"
        return 0
    fi
    
    return 1
}

# Function to prompt for input with validation (with optional auto-detected default)
prompt_input() {
    local prompt_text="$1"
    local var_name="$2"
    local validation_pattern="$3"
    local default_value="$4"
    local input_value
    
    while true; do
        if [[ -n "$default_value" ]]; then
            echo -n "$prompt_text (detected: $default_value): "
        else
            echo -n "$prompt_text: "
        fi
        
        read input_value
        
        # Use default if no input provided and default exists
        if [[ -z "$input_value" ]] && [[ -n "$default_value" ]]; then
            input_value="$default_value"
        fi
        
        if [[ -z "$input_value" ]]; then
            echo "Error: This field cannot be empty."
            continue
        fi
        
        if [[ -n "$validation_pattern" ]] && ! [[ "$input_value" =~ $validation_pattern ]]; then
            echo "Error: Invalid format. Please try again."
            continue
        fi
        
        eval "$var_name='$input_value'"
        break
    done
}

# Prompt for user inputs
echo "=== OpenShift Infrastructure MachineSet Generator ==="
echo ""

# Auto-detect cluster name, region, and AMI ID (skip if OC_SKIP_AUTODETECT is set)
if [[ "${OC_SKIP_AUTODETECT:-}" != "1" ]]; then
    echo "🔍 Attempting to auto-detect cluster information..."
    DETECTED_CLUSTER_NAME=$(auto_detect_cluster_name)
    DETECTED_REGION=$(auto_detect_aws_region)
    DETECTED_AMI_ID=$(auto_detect_ami_id)
else
    echo "⏭️  Skipping auto-detection (OC_SKIP_AUTODETECT=1)"
    DETECTED_CLUSTER_NAME=""
    DETECTED_REGION=""
    DETECTED_AMI_ID=""
fi

if [[ -n "$DETECTED_CLUSTER_NAME" ]]; then
    echo "✅ Detected cluster name: $DETECTED_CLUSTER_NAME"
else
    echo "⚠️  Could not auto-detect cluster name"
fi

if [[ -n "$DETECTED_REGION" ]]; then
    echo "✅ Detected AWS region: $DETECTED_REGION"
else
    echo "⚠️  Could not auto-detect AWS region"
fi

if [[ -n "$DETECTED_AMI_ID" ]]; then
    echo "✅ Detected AMI ID: $DETECTED_AMI_ID"
else
    echo "⚠️  Could not auto-detect AMI ID"
fi

echo ""

prompt_input "Enter cluster name" CLUSTER_NAME "^[a-zA-Z0-9][a-zA-Z0-9-]*[a-zA-Z0-9]$" "$DETECTED_CLUSTER_NAME"
prompt_input "Enter AWS region (e.g., us-east-1, eu-west-3)" REGION "^[a-z]{2}-[a-z]+-[0-9]+$" "$DETECTED_REGION"
prompt_input "Enter AMI ID (e.g., ami-1234567890abcdef0)" AMI_ID "^ami-[a-f0-9]{8,17}$" "$DETECTED_AMI_ID"
prompt_input "Enter EC2 instance type (e.g., c5.4xlarge, m5.2xlarge)" INSTANCE_TYPE "^[a-z][0-9]+[a-z]*\.[a-z0-9]+$" ""
prompt_input "Enter number of replicas per AZ (e.g., 1, 2, 3)" REPLICAS "^[1-9][0-9]*$" ""

# Prompt for availability zone suffixes (can be multiple, comma-separated)
echo -n "Enter availability zone suffixes, comma-separated (default: a): "
read AZ_SUFFIXES_INPUT
AZ_SUFFIXES_INPUT=${AZ_SUFFIXES_INPUT:-a}

# Parse and validate AZ suffixes
IFS=',' read -ra AZ_SUFFIXES <<< "$AZ_SUFFIXES_INPUT"
VALIDATED_AZ_SUFFIXES=()

for suffix in "${AZ_SUFFIXES[@]}"; do
    # Trim whitespace
    suffix=$(echo "$suffix" | xargs)
    
    # Validate AZ suffix
    if ! [[ "$suffix" =~ ^[a-z]$ ]]; then
        echo "Error: Availability zone suffix '$suffix' must be a single lowercase letter."
        exit 1
    fi
    
    VALIDATED_AZ_SUFFIXES+=("$suffix")
done

# Remove duplicates
UNIQUE_AZ_SUFFIXES=($(printf "%s\n" "${VALIDATED_AZ_SUFFIXES[@]}" | sort -u))

echo ""
echo "Generating MachineSet YAML files..."
echo "Cluster Name: $CLUSTER_NAME $(if [[ "$CLUSTER_NAME" == "$DETECTED_CLUSTER_NAME" ]] && [[ -n "$DETECTED_CLUSTER_NAME" ]]; then echo "(auto-detected)"; fi)"
echo "Region: $REGION $(if [[ "$REGION" == "$DETECTED_REGION" ]] && [[ -n "$DETECTED_REGION" ]]; then echo "(auto-detected)"; fi)"
echo "AMI ID: $AMI_ID $(if [[ "$AMI_ID" == "$DETECTED_AMI_ID" ]] && [[ -n "$DETECTED_AMI_ID" ]]; then echo "(auto-detected)"; fi)"
echo "Instance Type: $INSTANCE_TYPE"
echo "Replicas per AZ: $REPLICAS"
echo "Availability Zones: ${UNIQUE_AZ_SUFFIXES[*]}"
echo ""

GENERATED_FILES=()

# Generate a YAML file for each availability zone
for AZ_SUFFIX in "${UNIQUE_AZ_SUFFIXES[@]}"; do
    AVAILABILITY_ZONE="${REGION}${AZ_SUFFIX}"
    MACHINESET_NAME="${CLUSTER_NAME}-infra-${AVAILABILITY_ZONE}"
    OUTPUT_FILE="${CLUSTER_NAME}-infra-${AVAILABILITY_ZONE}-machineset.yml"
    
    echo "📄 Generating: $OUTPUT_FILE"
    
    cat > "$OUTPUT_FILE" << EOF
apiVersion: machine.openshift.io/v1beta1
kind: MachineSet
metadata:
  labels:
    machine.openshift.io/cluster-api-cluster: ${CLUSTER_NAME}
  name: ${MACHINESET_NAME}
  namespace: openshift-machine-api
spec:
  replicas: ${REPLICAS}
  selector:
    matchLabels:
      machine.openshift.io/cluster-api-cluster: ${CLUSTER_NAME}
      machine.openshift.io/cluster-api-machineset: ${MACHINESET_NAME}
  template:
    metadata:
      labels:
        machine.openshift.io/cluster-api-cluster: ${CLUSTER_NAME}
        machine.openshift.io/cluster-api-machine-role: infra
        machine.openshift.io/cluster-api-machine-type: infra
        machine.openshift.io/cluster-api-machineset: ${MACHINESET_NAME}
    spec:
      metadata:
        labels:
          node-role.kubernetes.io/infra: ""
      taints:
        - key: node-role.kubernetes.io/infra
          effect: NoSchedule
      providerSpec:
        value:
          ami:
            id: ${AMI_ID}
          apiVersion: machine.openshift.io/v1beta1
          blockDevices:
          - ebs:
              encrypted: true
              iops: 0
              volumeSize: 120
              volumeType: gp3
          credentialsSecret:
            name: aws-cloud-credentials
          deviceIndex: 0
          iamInstanceProfile:
            id: ${CLUSTER_NAME}-worker-profile
          instanceType: ${INSTANCE_TYPE}
          kind: AWSMachineProviderConfig
          placement:
            availabilityZone: ${AVAILABILITY_ZONE}
            region: ${REGION}
          securityGroups:
          - filters:
            - name: tag:Name
              values:
              - ${CLUSTER_NAME}-node
          - filters:
            - name: tag:Name
              values:
              - ${CLUSTER_NAME}-lb
          subnet:
            filters:
            - name: tag:Name
              values:
              - ${CLUSTER_NAME}-subnet-private-${AVAILABILITY_ZONE}
          tags:
          - name: kubernetes.io/cluster/${CLUSTER_NAME}
            value: owned
          userDataSecret:
            name: worker-user-data
EOF
    
    GENERATED_FILES+=("$OUTPUT_FILE")
done

echo ""
echo "✅ MachineSet YAML files generated successfully!"
echo ""
echo "Generated files:"
for file in "${GENERATED_FILES[@]}"; do
    echo "  📄 $file"
done

# Calculate total nodes
TOTAL_NODES=$((REPLICAS * ${#UNIQUE_AZ_SUFFIXES[@]}))
echo ""
echo "📊 Summary:"
echo "  • ${#UNIQUE_AZ_SUFFIXES[@]} Availability Zone(s): ${UNIQUE_AZ_SUFFIXES[*]}"
echo "  • $REPLICAS replica(s) per AZ"
echo "  • $TOTAL_NODES total infrastructure node(s) will be created"

echo ""
echo "To apply all MachineSets to your cluster, run:"
for file in "${GENERATED_FILES[@]}"; do
    echo "  oc apply -f $file"
done

echo ""
echo "Or apply all at once:"
echo "  oc apply -f ${CLUSTER_NAME}-infra-*-machineset.yml"

echo ""
if [[ "$AMI_ID" == "$DETECTED_AMI_ID" ]] && [[ -n "$DETECTED_AMI_ID" ]]; then
    echo "Note: AMI ID ($AMI_ID) was auto-detected from existing cluster machine sets."
    echo "This ensures compatibility with your current OpenShift cluster."
else
    echo "Note: Make sure the AMI ID ($AMI_ID) is compatible with your OpenShift cluster."
    echo "Consider using the same AMI as your existing worker nodes for consistency."
fi
