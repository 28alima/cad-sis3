import json
import os
import socket
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import boto3

events = boto3.client("events")
ddb = boto3.client("dynamodb")
BUS = os.environ["EVENT_BUS_NAME"]
TABLE = os.environ["TABLE_NAME"]


class Handler(BaseHTTPRequestHandler):
    def send_json(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/health":
            return self.send_json(200, {"status": "ok"})
        if self.path.startswith("/orders/"):
            order_id = self.path.split("/")[2]
            item = ddb.get_item(TableName=TABLE, Key={"orderId": {"S": order_id}}).get("Item")
            if not item:
                return self.send_json(404, {"orderId": order_id, "status": "NOT_FOUND"})
            return self.send_json(200, {"orderId": order_id, "status": "PROCESSED",
                                        "total": item["total"]["S"], "processedAt": item["processedAt"]["S"]})
        return self.send_json(200, {"service": "orders-api", "task": socket.gethostname()})

    def do_POST(self):
        if self.path != "/orders":
            return self.send_json(404, {"error": "not found"})
        try:
            length = int(self.headers.get("Content-Length", 0))
            body = json.loads(self.rfile.read(length) or b"{}")
        except ValueError:
            return self.send_json(400, {"error": "body must be JSON"})

        order_id = self.headers.get("Idempotency-Key") or "o-" + uuid.uuid4().hex[:8]
        detail = {"orderId": order_id, "total": body.get("total", 0)}
        if body.get("simulateBadEvent"):          # test only: an event without orderId -> goes to the DLQ
            detail = {"total": body.get("total", 0)}

        # Publish the domain event. PutEvents can return 200 with failed entries, so check the count.
        result = events.put_events(Entries=[{
            "EventBusName": BUS, "Source": "kbtu.shop.orders",
            "DetailType": "OrderPlaced", "Detail": json.dumps(detail),
        }])
        if result["FailedEntryCount"]:
            return self.send_json(502, {"error": "event not published"})
        print(json.dumps({"msg": "OrderPlaced published", "orderId": order_id}), flush=True)
        return self.send_json(202, {"orderId": order_id, "status": "ACCEPTED"})

    def log_message(self, fmt, *args):
        print(fmt % args, flush=True)


if __name__ == "__main__":
    ThreadingHTTPServer(("0.0.0.0", 8080), Handler).serve_forever()
