{{- define "env.name" -}}
datagrok-{{ required "env is required" .Values.env }}
{{- end -}}

{{- define "env.secretKeys" -}}
- adminPassword
- pgPassword
- pgAdminPassword
- rabbitmqPassword
- grokPipeApiKey
- spawnerApiKey
{{- end -}}

{{- define "env.computedAppValues" -}}
{{- $name := include "env.name" . }}
datagrok:
  image:
    tag: {{ .Values.datagrok.imageTag }}
{{- if .Values.datagrok.imageDigest }}
    digest: {{ .Values.datagrok.imageDigest }}
{{- end }}
  grokParametersExtra:
    keyStorageBackend: aws_secrets_manager
    keyStorageSecretPrefix: datagrok/server-keys/{{ .Values.env }}
  settings:
    logger:
      cloudWatchDefaultExport: true
      cloudWatchDefaultLogGroup: /datagrok/{{ .Values.env }}
      cloudWatchDefaultStream: datlas
      cloudWatchDefaultTypes: "error,audit,usage"
  resources:
    requests:
      cpu: "2"
      memory: 4Gi
    limits:
      cpu: "4"
      memory: 8Gi
postgres:
  internal: false
  useIamAuth: true
  region: {{ .Values.aws.region }}
  adminUser: datagrok_admin
  external:
    host: {{ .Values.db.host }}
    port: 5432
    ssl: true
  secretRefs:
    password:
      name: datagrok-pg
      key: pgPassword
storage:
  type: s3
  s3:
    bucket: {{ $name }}
    region: {{ .Values.aws.region }}
serviceAccount:
  create: true
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::{{ .Values.aws.accountId }}:role/{{ $name }}-app
ingress:
  enabled: true
  className: alb
  host: {{ required "hostname is required" .Values.hostname }}
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP":80},{"HTTPS":443}]'
    alb.ingress.kubernetes.io/ssl-redirect: "443"
    alb.ingress.kubernetes.io/ssl-policy: ELBSecurityPolicy-TLS13-1-2-2021-06
{{- with .Values.ingress.certificateArn }}
    alb.ingress.kubernetes.io/certificate-arn: {{ . }}
{{- end }}
  tls:
    enabled: false
spawner:
  mode: kubernetes
registry:
  type: none
credentials:
  source: externalSecrets
  externalSecrets:
    enabled: true
    secretStore: aws-secrets-manager
    secretStoreKind: ClusterSecretStore
    remoteKey: datagrok/{{ .Values.env }}
{{- end -}}
