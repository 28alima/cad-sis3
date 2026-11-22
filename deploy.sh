#!/usr/bin/env bash
# One command deploys everything:  ./deploy.sh [prefix] [env]     e.g. ./deploy.sh sis3 dev
set -euo pipefail
PREFIX="${1:-sis3}"
ENV="${2:-dev}"
REGION="${AWS_REGION:-ap-southeast-2}"
cd "$(dirname "$0")"
D="sam deploy --region $REGION --no-confirm-changeset --no-fail-on-empty-changeset"

echo "== 1/5 network stack"
$D --template-file infra/network.yaml --stack-name "$PREFIX-network" --parameter-overrides Env="$ENV"

echo "== 2/5 data + messaging stack"
$D --template-file infra/data.yaml --stack-name "$PREFIX-data" --parameter-overrides Env="$ENV" \
   --resolve-s3 --capabilities CAPABILITY_IAM CAPABILITY_AUTO_EXPAND

echo "== 3/5 container registry stack"
$D --template-file infra/ecr.yaml --stack-name "$PREFIX-ecr"

echo "== 4/5 build and push the image"
REPO_URI=$(aws cloudformation describe-stacks --region "$REGION" --stack-name "$PREFIX-ecr" \
  --query "Stacks[0].Outputs[?OutputKey=='RepoUri'].OutputValue" --output text)
TAG=$(git rev-parse --short HEAD 2>/dev/null || date +%Y%m%d-%H%M%S)
if aws ecr describe-images --region "$REGION" --repository-name "${REPO_URI#*/}" --image-ids imageTag="$TAG" >/dev/null 2>&1; then
  echo "image $TAG already in ECR (tags are immutable) - skipping build"
else
  aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "${REPO_URI%%/*}"
  docker build -t "$REPO_URI:$TAG" app/
  docker push "$REPO_URI:$TAG"
fi

echo "== 5/5 application stack (ECS Fargate + ALB), image tag $TAG"
$D --template-file infra/app.yaml --stack-name "$PREFIX-app" --capabilities CAPABILITY_IAM \
   --parameter-overrides Prefix="$PREFIX" Env="$ENV" ImageTag="$TAG"

URL=$(aws cloudformation describe-stacks --region "$REGION" --stack-name "$PREFIX-app" \
  --query "Stacks[0].Outputs[?OutputKey=='ServiceUrl'].OutputValue" --output text)
echo "DONE. Service URL: $URL"
