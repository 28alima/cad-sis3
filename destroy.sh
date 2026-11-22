#!/usr/bin/env bash
# Deletes all four stacks in reverse order:  ./destroy.sh [prefix]
set -euo pipefail
PREFIX="${1:-sis3}"
REGION="${AWS_REGION:-ap-southeast-2}"
for s in app ecr data network; do
  echo "== deleting $PREFIX-$s"
  aws cloudformation delete-stack --region "$REGION" --stack-name "$PREFIX-$s"
  aws cloudformation wait stack-delete-complete --region "$REGION" --stack-name "$PREFIX-$s"
done
echo "All stacks deleted."
