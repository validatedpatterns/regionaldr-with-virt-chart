# regionaldr-with-virt

![Version: 0.0.1](https://img.shields.io/badge/Version-0.0.1-informational?style=flat-square)

A Helm chart to deploy RegionalDR configuration including virtualization

This chart provides a Regional DR configuration

## Notable changes

v0.1.0 - Initial release

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| ansible.containerImage | string | `"quay.io/validatedpatterns/utility-container:latest"` |  |
| boutique.chartName | string | `"boutique"` |  |
| boutique.chartVersion | string | `"0.0.4"` |  |
| boutique.deploy | bool | `false` |  |
| boutique.helmRepoAlias | string | `"validatedpatterns"` |  |
| boutique.helmRepoUrl | string | `"https://charts.validatedpatterns.io"` |  |
| boutique.namespace | string | `"boutique"` |  |
| clusterDeployments.awsSecretKey | string | `"secret/hub/aws"` |  |
| clusterDeployments.pullSecretKey | string | `"secret/hub/openshiftPullSecret"` |  |
| clusterDeployments.secretRefreshInterval | string | `"90s"` |  |
| drpc.drPolicyRef.name | string | `"2m-vm"` |  |
| drpc.healthCheck.deleteWaitDelay | int | `5` |  |
| drpc.healthCheck.deleteWaitRetries | int | `24` |  |
| drpc.healthCheck.maxAttempts | int | `30` |  |
| drpc.healthCheck.retryDelaySeconds | int | `30` |  |
| drpc.kubeObjectProtection.captureInterval | string | `"2m0s"` |  |
| drpc.kubeObjectProtection.kubeObjectSelector | object | `{}` |  |
| drpc.name | string | `"gitops-vm-protection"` |  |
| drpc.namespace | string | `"openshift-dr-ops"` |  |
| drpc.placementRef.name | string | `"gitops-vm-protection-placement-1"` |  |
| drpc.placementRef.namespace | string | `"openshift-dr-ops"` |  |
| drpc.preferredCluster | string | `"ocp-primary"` |  |
| drpc.protectedNamespaces[0] | string | `"gitops-vms"` |  |
| drpc.pvcSelector | object | `{}` |  |
| edgeGitopsVms.chartVersion | string | `"0.3.0"` |  |
| global.clusterDomain | string | `"cluster.example.com"` |  |
| global.pattern | string | `"ramendr-starter-kit-hub"` |  |
| main.clusterGroupName | string | `"resilient"` |  |
| odfRamenTrustedCa.pollInterval | int | `15` |  |
| odfRamenTrustedCa.ramenS3WaitSeconds | int | `3600` |  |
| odfRamenTrustedCa.trustedCaWaitSeconds | int | `3600` |  |
| redis.external.address | string | `"rhel9-redis-001.gitops-vms.svc.cluster.local"` |  |
| redis.external.enabled | bool | `false` |  |
| regionalDR[0].clusters.primary.clusterGroup | string | `"resilient"` |  |
| regionalDR[0].clusters.primary.install_config.apiVersion | string | `"v1"` |  |
| regionalDR[0].clusters.primary.install_config.baseDomain | string | `"{{ join \".\" (slice (splitList \".\" $.Values.global.clusterDomain) 1) }}"` |  |
| regionalDR[0].clusters.primary.install_config.compute[0].name | string | `"worker"` |  |
| regionalDR[0].clusters.primary.install_config.compute[0].platform.aws.type | string | `"m5.metal"` |  |
| regionalDR[0].clusters.primary.install_config.compute[0].replicas | int | `3` |  |
| regionalDR[0].clusters.primary.install_config.controlPlane.name | string | `"master"` |  |
| regionalDR[0].clusters.primary.install_config.controlPlane.platform.aws.type | string | `"m5.4xlarge"` |  |
| regionalDR[0].clusters.primary.install_config.controlPlane.replicas | int | `3` |  |
| regionalDR[0].clusters.primary.install_config.metadata.name | string | `"ocp-primary"` |  |
| regionalDR[0].clusters.primary.install_config.networking.clusterNetwork[0].cidr | string | `"10.132.0.0/14"` |  |
| regionalDR[0].clusters.primary.install_config.networking.clusterNetwork[0].hostPrefix | int | `23` |  |
| regionalDR[0].clusters.primary.install_config.networking.machineNetwork[0].cidr | string | `"10.1.0.0/16"` |  |
| regionalDR[0].clusters.primary.install_config.networking.networkType | string | `"OVNKubernetes"` |  |
| regionalDR[0].clusters.primary.install_config.networking.serviceNetwork[0] | string | `"172.20.0.0/16"` |  |
| regionalDR[0].clusters.primary.install_config.platform.aws.region | string | `"us-west-1"` |  |
| regionalDR[0].clusters.primary.install_config.platform.aws.userTags.project | string | `"ValidatedPatterns"` |  |
| regionalDR[0].clusters.primary.install_config.publish | string | `"External"` |  |
| regionalDR[0].clusters.primary.install_config.pullSecret | string | `""` |  |
| regionalDR[0].clusters.primary.install_config.sshKey | string | `""` |  |
| regionalDR[0].clusters.primary.name | string | `"ocp-primary"` |  |
| regionalDR[0].clusters.primary.version | string | `"4.18.7"` |  |
| regionalDR[0].clusters.secondary.clusterGroup | string | `"resilient"` |  |
| regionalDR[0].clusters.secondary.install_config.apiVersion | string | `"v1"` |  |
| regionalDR[0].clusters.secondary.install_config.baseDomain | string | `"{{ join \".\" (slice (splitList \".\" $.Values.global.clusterDomain) 1) }}"` |  |
| regionalDR[0].clusters.secondary.install_config.compute[0].name | string | `"worker"` |  |
| regionalDR[0].clusters.secondary.install_config.compute[0].platform.aws.type | string | `"m5.metal"` |  |
| regionalDR[0].clusters.secondary.install_config.compute[0].replicas | int | `3` |  |
| regionalDR[0].clusters.secondary.install_config.controlPlane.name | string | `"master"` |  |
| regionalDR[0].clusters.secondary.install_config.controlPlane.platform.aws.type | string | `"m5.4xlarge"` |  |
| regionalDR[0].clusters.secondary.install_config.controlPlane.replicas | int | `3` |  |
| regionalDR[0].clusters.secondary.install_config.metadata.name | string | `"ocp-secondary"` |  |
| regionalDR[0].clusters.secondary.install_config.networking.clusterNetwork[0].cidr | string | `"10.136.0.0/14"` |  |
| regionalDR[0].clusters.secondary.install_config.networking.clusterNetwork[0].hostPrefix | int | `23` |  |
| regionalDR[0].clusters.secondary.install_config.networking.machineNetwork[0].cidr | string | `"10.2.0.0/16"` |  |
| regionalDR[0].clusters.secondary.install_config.networking.networkType | string | `"OVNKubernetes"` |  |
| regionalDR[0].clusters.secondary.install_config.networking.serviceNetwork[0] | string | `"172.21.0.0/16"` |  |
| regionalDR[0].clusters.secondary.install_config.platform.aws.region | string | `"us-east-1"` |  |
| regionalDR[0].clusters.secondary.install_config.platform.aws.userTags.project | string | `"ValidatedPatterns"` |  |
| regionalDR[0].clusters.secondary.install_config.publish | string | `"External"` |  |
| regionalDR[0].clusters.secondary.install_config.pullSecret | string | `""` |  |
| regionalDR[0].clusters.secondary.install_config.sshKey | string | `""` |  |
| regionalDR[0].clusters.secondary.name | string | `"ocp-secondary"` |  |
| regionalDR[0].clusters.secondary.version | string | `"4.18.7"` |  |
| regionalDR[0].drpolicies[0].interval | string | `"2m"` |  |
| regionalDR[0].drpolicies[0].vmSupport | bool | `true` |  |
| regionalDR[0].drpolicies[1].interval | string | `"2m"` |  |
| regionalDR[0].globalnetEnabled | bool | `false` |  |
| regionalDR[0].name | string | `"resilient"` |  |
| secretStore.kind | string | `"ClusterSecretStore"` |  |
| secretStore.name | string | `"vault-backend"` |  |
| submariner.NATTEnable | bool | `true` |  |
| submariner.cableDriver | string | `"vxlan"` |  |
| submariner.instanceType | string | `"m5.xlarge"` |  |
| submariner.ipsecNatPort | int | `4500` |  |

----------------------------------------------
Autogenerated from chart metadata using [helm-docs v1.14.2](https://github.com/norwoodj/helm-docs/releases/v1.14.2)
