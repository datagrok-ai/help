{{- define "mon.role" -}}
{{- if not (has .Values.role (list "standalone" "agent" "hub")) }}
{{- fail (printf "role: %v. Use standalone, agent or hub" .Values.role) }}
{{- end }}
{{- $_ := required "cluster is required: the value of the cluster label" .Values.cluster }}
{{- .Values.role }}
{{- end -}}

{{/* "true" when this cluster stores and alerts. */}}
{{- define "mon.hub" -}}
{{- if has (include "mon.role" .) (list "standalone" "hub") }}true{{ end }}
{{- end -}}

{{/* "true" when this cluster collects from Datagrok instances. */}}
{{- define "mon.agent" -}}
{{- if has (include "mon.role" .) (list "standalone" "agent") }}true{{ end }}
{{- end -}}

{{/* Labels of the objects a Prometheus operator selects. */}}
{{- define "mon.objectLabels" -}}
{{- with .Values.stack.objectLabels }}
{{- toYaml . }}
{{- end }}
{{- end -}}

{{- define "mon.retry" -}}
{limit: -1, backoff: {duration: 30s, factor: 2, maxDuration: 5m}}
{{- end -}}

{{/* A host name as an RE2 pattern inside an OTTL string literal. */}}
{{- define "mon.ottlHostPattern" -}}
{{- regexQuoteMeta . | replace "\\" "\\\\" }}
{{- end -}}
