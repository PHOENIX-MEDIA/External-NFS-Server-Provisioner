{{/*
Expand the name of the chart.
*/}}
{{- define "nfs-server-provisioner.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "nfs-server-provisioner.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "nfs-server-provisioner.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "nfs-server-provisioner.labels" -}}
helm.sh/chart: {{ include "nfs-server-provisioner.chart" . }}
{{ include "nfs-server-provisioner.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "nfs-server-provisioner.selectorLabels" -}}
app.kubernetes.io/name: {{ include "nfs-server-provisioner.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Return persistent volume claim
*/}}
{{- define "nfs-server-provisioner.pvcName" -}}
{{- if .Values.persistence.existingClaim }}
{{- print .Values.persistence.existingClaim }}
{{- else if .Values.persistence.name -}}
{{- print .Values.persistence.name }}
{{- else -}}
{{- printf "%s-data" (include "nfs-server-provisioner.fullname" .) }}
{{- end -}}
{{- end -}}
