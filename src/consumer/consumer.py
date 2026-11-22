import json
import os
from datetime import datetime, timezone

import boto3
from botocore.exceptions import ClientError

table = boto3.resource("dynamodb").Table(os.environ["TABLE_NAME"])


def handler(event, context):
    failed = []
    for record in event["Records"]:
        order_id = None
        try:
            body = json.loads(record["body"])
            order = body.get("detail", body)          # EventBridge puts the order into "detail"
            order_id = order["orderId"]               # the deduplication key
            # Idempotency: write only if this orderId was never processed before
            table.put_item(
                Item={
                    "orderId": order_id,
                    "total": str(order.get("total", "0")),
                    "processedAt": datetime.now(timezone.utc).isoformat(),
                },
                ConditionExpression="attribute_not_exists(orderId)",
            )
            print(json.dumps({"msg": "processed", "orderId": order_id}))
        except ClientError as e:
            if e.response["Error"]["Code"] == "ConditionalCheckFailedException":
                print(json.dumps({"msg": "duplicate skipped", "orderId": order_id}))
            else:
                print(json.dumps({"msg": "error", "error": str(e)}))
                failed.append({"itemIdentifier": record["messageId"]})
        except Exception as e:
            print(json.dumps({"msg": "bad message", "error": str(e)}))
            failed.append({"itemIdentifier": record["messageId"]})
    return {"batchItemFailures": failed}       # only failed records go back to the queue
