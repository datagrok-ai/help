#! /bin/bash
# Generates every deployment profile: {network,vpc} x {fargate,eks} x {r53,dns} x {basic,marketplace}.
# common.template.yml holds the ALB, RDS, S3 and secrets shared by ECS and EKS, so replacing an
# ECS stack's template with the matching EKS one keeps the database and the bucket
# (see deploy-amazon-eks.mdx#migrate-from-ecs).

set -e
cd "$(dirname "$0")"
python=${PYTHON:-python3}

for network in network:create_network vpc:choose_vpc; do
  for compute in fargate eks; do
    for dns in r53 dns; do
      for offer in basic marketplace; do
        "$python" templates/cf_template_merge.py \
          -i "templates/${network#*:}.template.yml" \
          -i templates/common.template.yml \
          -i "templates/${compute}.template.yml" \
          -i "templates/${dns}.template.yml" \
          -i "templates/${offer}.template.yml" \
          -i templates/versions.template.yml \
          -o "${network%%:*}-${compute}-${dns}-${offer}.yml"
      done
    done
  done
done
