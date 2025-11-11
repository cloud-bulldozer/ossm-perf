# OSSM-Perf

Performance & Scale resources for OpenShift Service Mesh:

## Available tests

- [Control plane](control-plane/README.md)
- [N/S networking](data-plane/ingress/)
- [E/W networking](data-plane/networking/README.md)

## Preparations

For most of the benchmarks, it is beneficial to allocate dedicated [infrastructure nodes](https://docs.redhat.com/en/documentation/openshift_container_platform/4.18/html/machine_management/creating-infrastructure-machinesets#assigning-machineset-resources-to-infra-nodes). This allows to isolate infra components, ensuring more deterministic and repeatable results:
* Generate infra MachineSets with the [infraset-generator-aws.sh](resources/infraset-generator-aws.sh) script and apply them
* Once infra nodes are available, run the [move-ocp-components-to-infra.sh](resources/move-ocp-components-to-infra.sh) script to
move ingress, image registry and monitoring stack to infra nodes