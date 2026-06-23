{{/*
  Sanitize install_config for OpenShift installer: ensure apiVersion, pass through all
  install-config fields (including full platform.aws: region, subnets, userTags, amiID,
  defaultMachinePlatform, serviceEndpoints, etc.) so regionalDR and clusterOverrides
  can override platform/region effectively. Only strip keys known invalid for the
  installer (e.g. vpc in platform.aws).
*/}}
{{- define "rdr.sanitizeInstallConfig" -}}
{{- $raw := . -}}
{{- $withVersion := merge (dict "apiVersion" "v1") $raw -}}
{{- $platform := index $withVersion "platform" | default dict -}}
{{- $aws := index $platform "aws" | default dict -}}
{{- /* Pass through full platform.aws (region, subnets, userTags, amiID, defaultMachinePlatform, serviceEndpoints, etc.); omit only known-invalid keys like vpc */ -}}
{{- $awsSafe := ternary (omit $aws "vpc") $aws (and (kindIs "map" $aws) (hasKey $aws "vpc")) -}}
{{- $platformSafe := merge (dict "aws" $awsSafe) $platform -}}
{{- $allowed := dict "apiVersion" (index $withVersion "apiVersion") "baseDomain" (index $withVersion "baseDomain") "metadata" (index $withVersion "metadata") "controlPlane" (index $withVersion "controlPlane") "compute" (index $withVersion "compute") "networking" (index $withVersion "networking") "platform" $platformSafe "publish" (index $withVersion "publish") "pullSecret" (index $withVersion "pullSecret") "sshKey" (index $withVersion "sshKey") -}}
{{- $allowed | toJson -}}
{{- end -}}

{{/*
  Deep-merge install_config so clusterOverrides can override only platform/region,
  metadata, or any subset without replacing the rest of base install_config.
  Call with dict "base" <base install_config> "over" <override install_config>.
*/}}
{{- define "rdr.mergeInstallConfig" -}}
{{- $base := .base | default dict -}}
{{- $over := .over | default dict -}}
{{- /* Sprig merge: first dict wins; put over first so override wins */ -}}
{{- $merged := merge $over $base -}}
{{- $metadataMerged := merge (index $over "metadata" | default dict) (index $base "metadata" | default dict) -}}
{{- $merged := merge (dict "metadata" $metadataMerged) $merged -}}
{{- $platformBase := index $base "platform" | default dict -}}
{{- $platformOver := index $over "platform" | default dict -}}
{{- $awsBase := index $platformBase "aws" | default dict -}}
{{- $awsOver := index $platformOver "aws" | default dict -}}
{{- $awsMerged := merge $awsOver $awsBase -}}
{{- $platformFinal := merge (dict "aws" $awsMerged) $platformBase -}}
{{- merge (dict "platform" $platformFinal) $merged | toJson -}}
{{- end -}}

{{/*
  Effective primary cluster: merge of regionalDR[0].clusters.primary and clusterOverrides.primary.
  Use when clusterOverrides is set to avoid replacing full regionalDR in override file.
  Call with a context that has .Values and optionally .primaryOverrideInstallConfig (override install_config);
  if primaryOverrideInstallConfig is not provided, falls back to .Values.clusterOverrides.primary.install_config.
*/}}
{{- define "rdr.effectivePrimaryCluster" -}}
{{- $dr := index .Values.regionalDR 0 -}}
{{- $over := index (.Values.clusterOverrides | default dict) "primary" | default dict -}}
{{- $base := $dr.clusters.primary -}}
{{- $baseIC := $base.install_config | default dict -}}
{{- /* When values-hub (or similar) replaces regionalDR with minimal structure, base has no install_config; use chart default */ -}}
{{- if and (index . "Files") (not (hasKey $baseIC "controlPlane")) -}}
{{- $baseIC = fromJson ((index . "Files").Get "files/default-primary-install-config.json") | default dict -}}
{{- end -}}
{{- $overIC := index . "primaryOverrideInstallConfig" | default $over.install_config | default dict -}}
{{- /* Shallow merge: over wins. Deep-merge metadata, platform.aws, controlPlane, compute so over wins but base keeps machine types when over is partial. */ -}}
{{- $merged := merge $overIC $baseIC -}}
{{- $metadataMerged := merge (index $overIC "metadata" | default dict) (index $baseIC "metadata" | default dict) -}}
{{- $merged := merge (dict "metadata" $metadataMerged) $merged -}}
{{- $platformBase := index $baseIC "platform" | default dict -}}
{{- $awsBase := index $platformBase "aws" | default dict -}}
{{- $awsOver := index (index $overIC "platform" | default dict) "aws" | default dict -}}
{{- $awsMerged := merge $awsOver $awsBase -}}
{{- $platformFinal := merge (dict "aws" $awsMerged) $platformBase -}}
{{- $merged := merge (dict "platform" $platformFinal) $merged -}}
{{- /* Deep-merge controlPlane so override can set platform.aws.type without dropping base name/replicas */ -}}
{{- $cpBase := index $baseIC "controlPlane" | default dict -}}
{{- $cpOver := index $overIC "controlPlane" | default dict -}}
{{- $cpMerged := merge $cpOver $cpBase -}}
{{- $cpPlatformBase := index $cpBase "platform" | default dict -}}
{{- $cpPlatformOver := index $cpOver "platform" | default dict -}}
{{- $cpAwsBase := index $cpPlatformBase "aws" | default dict -}}
{{- $cpAwsOver := index $cpPlatformOver "aws" | default dict -}}
{{- $cpAwsMerged := merge $cpAwsOver $cpAwsBase -}}
{{- $cpPlatformFinal := merge (dict "aws" $cpAwsMerged) $cpPlatformBase -}}
{{- $controlPlaneFinal := merge (dict "platform" $cpPlatformFinal) $cpMerged -}}
{{- $merged := merge (dict "controlPlane" $controlPlaneFinal) $merged -}}
{{- /* Compute: override list wins if non-empty; else use base so base machine types are kept */ -}}
{{- $computeBase := index $baseIC "compute" | default list -}}
{{- $computeOver := index $overIC "compute" | default list -}}
{{- $computeFinal := ternary $computeOver $computeBase (gt (len $computeOver) 0) -}}
{{- $installConfig := merge (dict "compute" $computeFinal) $merged -}}
{{- $installConfigSafe := fromJson (include "rdr.sanitizeInstallConfig" $installConfig) -}}
{{- $defaultBaseDomain := join "." (slice (splitList "." (.Values.global.clusterDomain | default "cluster.example.com")) 1) -}}
{{- $installConfigWithBase := merge (dict "baseDomain" ($defaultBaseDomain | default (index $installConfigSafe "baseDomain"))) $installConfigSafe -}}
{{- $clusterGroup := index $over "clusterGroup" | default $base.clusterGroup | default $dr.name -}}
{{- dict "name" (index $over "name" | default $base.name) "version" (index $over "version" | default $base.version) "clusterGroup" $clusterGroup "install_config" $installConfigWithBase | toJson -}}
{{- end -}}

{{/*
  Effective secondary cluster: merge of regionalDR[0].clusters.secondary and clusterOverrides.secondary.
  Call with a context that has .Values and optionally .secondaryOverrideInstallConfig.
*/}}
{{- define "rdr.effectiveSecondaryCluster" -}}
{{- $dr := index .Values.regionalDR 0 -}}
{{- $over := index (.Values.clusterOverrides | default dict) "secondary" | default dict -}}
{{- $base := $dr.clusters.secondary -}}
{{- $baseIC := $base.install_config | default dict -}}
{{- if and (index . "Files") (not (hasKey $baseIC "controlPlane")) -}}
{{- $baseIC = fromJson ((index . "Files").Get "files/default-secondary-install-config.json") | default dict -}}
{{- end -}}
{{- $overIC := index . "secondaryOverrideInstallConfig" | default $over.install_config | default dict -}}
{{- $merged := merge $overIC $baseIC -}}
{{- $metadataMerged := merge (index $overIC "metadata" | default dict) (index $baseIC "metadata" | default dict) -}}
{{- $merged := merge (dict "metadata" $metadataMerged) $merged -}}
{{- $platformBase := index $baseIC "platform" | default dict -}}
{{- $awsBase := index $platformBase "aws" | default dict -}}
{{- $awsOver := index (index $overIC "platform" | default dict) "aws" | default dict -}}
{{- $awsMerged := merge $awsOver $awsBase -}}
{{- $platformFinal := merge (dict "aws" $awsMerged) $platformBase -}}
{{- $merged := merge (dict "platform" $platformFinal) $merged -}}
{{- $cpBase := index $baseIC "controlPlane" | default dict -}}
{{- $cpOver := index $overIC "controlPlane" | default dict -}}
{{- $cpMerged := merge $cpOver $cpBase -}}
{{- $cpPlatformBase := index $cpBase "platform" | default dict -}}
{{- $cpPlatformOver := index $cpOver "platform" | default dict -}}
{{- $cpAwsBase := index $cpPlatformBase "aws" | default dict -}}
{{- $cpAwsOver := index $cpPlatformOver "aws" | default dict -}}
{{- $cpAwsMerged := merge $cpAwsOver $cpAwsBase -}}
{{- $cpPlatformFinal := merge (dict "aws" $cpAwsMerged) $cpPlatformBase -}}
{{- $controlPlaneFinal := merge (dict "platform" $cpPlatformFinal) $cpMerged -}}
{{- $merged := merge (dict "controlPlane" $controlPlaneFinal) $merged -}}
{{- $computeBase := index $baseIC "compute" | default list -}}
{{- $computeOver := index $overIC "compute" | default list -}}
{{- $computeFinal := ternary $computeOver $computeBase (gt (len $computeOver) 0) -}}
{{- $installConfig := merge (dict "compute" $computeFinal) $merged -}}
{{- $installConfigSafe := fromJson (include "rdr.sanitizeInstallConfig" $installConfig) -}}
{{- $defaultBaseDomain := join "." (slice (splitList "." (.Values.global.clusterDomain | default "cluster.example.com")) 1) -}}
{{- $installConfigWithBase := merge (dict "baseDomain" ($defaultBaseDomain | default (index $installConfigSafe "baseDomain"))) $installConfigSafe -}}
{{- $clusterGroup := index $over "clusterGroup" | default $base.clusterGroup | default $dr.name -}}
{{- dict "name" (index $over "name" | default $base.name) "version" (index $over "version" | default $base.version) "clusterGroup" $clusterGroup "install_config" $installConfigWithBase | toJson -}}
{{- end -}}

{{/* Primary cluster name for use in drpc, jobs, etc. */}}
{{- define "rdr.primaryClusterName" -}}
{{- $dr := index .Values.regionalDR 0 -}}
{{- index (index (.Values.clusterOverrides | default dict) "primary" | default dict) "name" | default $dr.clusters.primary.name -}}
{{- end -}}

{{/* Secondary cluster name */}}
{{- define "rdr.secondaryClusterName" -}}
{{- $dr := index .Values.regionalDR 0 -}}
{{- index (index (.Values.clusterOverrides | default dict) "secondary" | default dict) "name" | default $dr.clusters.secondary.name -}}
{{- end -}}

{{/* Preferred cluster for DRPC (default: primary). Override via values.drpc.preferredCluster. */}}
{{- define "rdr.preferredClusterName" -}}
{{- (index (.Values.drpc | default dict) "preferredCluster") | default (include "rdr.primaryClusterName" .) -}}
{{- end -}}

{{/* regionalDR[0].name (ClusterSet); Submariner broker namespace = name + "-broker" */}}
{{- define "rdr.regionalDRClusterSetName" -}}
{{- $dr := index .Values.regionalDR 0 -}}
{{- $dr.name -}}
{{- end -}}

{{- define "rdr.submarinerBrokerNamespace" -}}
{{ include "rdr.regionalDRClusterSetName" . }}-broker
{{- end -}}

{{/* global.clusterPlatform (e.g. AWS, BareMetal, GCP): AWS gates AWS-only chart pieces. Case-insensitive; default AWS preserves prior behavior. */}}
{{- define "rdr.clusterPlatformAws" -}}
{{- $g := .Values.global | default dict -}}
{{- if eq "aws" (lower ($g.clusterPlatform | default "AWS" | toString)) -}}1{{- else -}}0{{- end -}}
{{- end -}}

{{/* Submariner EC2 SG tagger job + RBAC: AWS platform and submariner.sgTagJobEnabled true. */}}
{{- define "rdr.submarinerSgTagJobEnabled" -}}
{{- $sm := .Values.submariner | default dict -}}
{{- $aws := eq "1" (include "rdr.clusterPlatformAws" . | trim) -}}
{{- $want := and (hasKey $sm "sgTagJobEnabled") (index $sm "sgTagJobEnabled") -}}
{{- if and $aws $want -}}1{{- else -}}0{{- end -}}
{{- end -}}

{{/* ODF post-install fixes: prerequisites checker + Ramen trusted CA jobs/RBAC. Default on if .Values.odf.postInstallFixesEnabled omitted. */}}
{{- define "rdr.odfPostInstallFixesEnabled" -}}
{{- $odf := .Values.odf | default dict -}}
{{- if not (hasKey $odf "postInstallFixesEnabled") -}}1{{- else if index $odf "postInstallFixesEnabled" -}}1{{- else -}}0{{- end -}}
{{- end -}}

{{/* Namespace for ODF CA post-install Jobs (cluster-proxy-ca-bundle stays in openshift-config). */}}
{{- define "rdr.clusterCaMgtNamespace" -}}
{{- .Values.clusterCaMgt.namespace | default "cluster-ca-mgt" -}}
{{- end -}}
{{/* Stable checksum of packaged ansible/ (excludes dotfiles). Drives CM + Job drift on chart updates. */}}
{{- define "rdr.ansibleConfigChecksum" -}}
{{- $paths := list -}}
{{- range $path, $_ := .Files.Glob "ansible/**" -}}
{{- if not (hasPrefix "ansible/." $path) -}}
{{- $paths = append $paths $path -}}
{{- end -}}
{{- end -}}
{{- $buf := "" -}}
{{- range $path := $paths | sortAlpha -}}
{{- $buf = printf "%s\n%s\n%s" $buf $path ($.Files.Get $path) -}}
{{- end -}}
{{- $buf | sha256sum -}}
{{- end -}}

{{/* Argo CD sync-options for regionaldr-ansible (see values ansible.configMapArgoSyncOptions). */}}
{{- define "rdr.ansibleConfigMapArgoSyncOptions" -}}
{{- .Values.ansible.configMapArgoSyncOptions | default "Prune=false,ServerSideApply=true" -}}
{{- end -}}

{{/* Pod template annotation: keep ansible Jobs in sync with regionaldr-ansible content. */}}
{{- define "rdr.ansibleJobPodAnnotations" -}}
checksum/regionaldr-ansible: {{ include "rdr.ansibleConfigChecksum" . | quote }}
{{- end -}}
