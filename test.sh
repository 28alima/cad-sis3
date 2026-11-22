#!/usr/bin/env bash
# Smoke and negative tests against a deployed copy:  ./test.sh [prefix]
set -uo pipefail
PREFIX="${1:-sis3}"
REGION="${AWS_REGION:-ap-southeast-2}"
out() { aws cloudformation describe-stacks --region "$REGION" --stack-name "$1" --query "Stacks[0].Outputs[?OutputKey=='$2'].OutputValue" --output text; }
URL=$(out "$PREFIX-app" ServiceUrl); TG=$(out "$PREFIX-app" TargetGroupArn); DLQ=$(out "$PREFIX-data" DlqUrl)
ID="o-$(date +%H%M%S)"
echo "Service: $URL"
echo "=== 1. Healthy targets";  aws elbv2 describe-target-health --region "$REGION" --target-group-arn "$TG" --query "TargetHealthDescriptions[].[Target.Id,TargetHealth.State]" --output table
echo "=== 2. Two tasks answer"; for i in 1 2 3 4; do curl -s "$URL/"; echo; done
echo "=== 3. New order $ID";   curl -s -X POST "$URL/orders" -H "content-type: application/json" -H "Idempotency-Key: $ID" -d '{"total":48}'; echo
echo "=== 4. Same order again (duplicate)"; curl -s -X POST "$URL/orders" -H "content-type: application/json" -H "Idempotency-Key: $ID" -d '{"total":48}'; echo
echo "=== 5. Bad event (no orderId) -> DLQ after 5 tries"; curl -s -X POST "$URL/orders" -H "content-type: application/json" -d '{"total":5,"simulateBadEvent":true}'; echo
sleep 10
echo "=== 6. Order status (processed once)"; curl -s "$URL/orders/$ID"; echo
echo "=== 7. Unknown order";  curl -s "$URL/orders/nope"; echo
echo "=== 8. Messages in DLQ (becomes 1 about 5 minutes after test 5)"
aws sqs get-queue-attributes --region "$REGION" --queue-url "$DLQ" --attribute-names ApproximateNumberOfMessages --query "Attributes.ApproximateNumberOfMessages" --output text
