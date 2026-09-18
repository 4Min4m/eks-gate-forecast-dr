"""
DR proof-of-concept endpoint.

WHY A LAMBDA INSTEAD OF ADDING A ROUTE TO go-httpbin: go-httpbin is a
prebuilt third-party image (mccutchen/go-httpbin) with no source in this
repo to add a custom handler to. Forking and maintaining a custom image just
for one trivial DR-test endpoint would be a bigger, messier change than the
PLAN's "keep the app-layer change minimal" intent. A tiny Lambda behind its
own API path is a smaller blast radius, needs no image build/push/ECR step,
and is trivially deployable to a second region — which is the actual point
of this exercise.

Behavior:
  GET  /dr-check       -> read the one item, return which region served it
  POST /dr-check       -> write/update the one item with a timestamp + region

Both regions run this exact same code; only the DynamoDB table's local
endpoint differs (Global Tables handle replicating the data between them).
"""
import datetime
import json
import os

import boto3

REGION = os.environ["AWS_REGION"]
TABLE_NAME = os.environ["TABLE_NAME"]
ITEM_ID = "dr-poc-singleton"

table = boto3.resource("dynamodb", region_name=REGION).Table(TABLE_NAME)


def handler(event, context):
    method = event.get("requestContext", {}).get("http", {}).get("method", "GET")

    if method == "POST":
        item = {
            "id": ITEM_ID,
            "written_by_region": REGION,
            "written_at": datetime.datetime.utcnow().isoformat() + "Z",
        }
        table.put_item(Item=item)
        body = {"action": "write", **item}
    else:
        resp = table.get_item(Key={"id": ITEM_ID})
        item = resp.get("Item")
        body = {"action": "read", "served_by_region": REGION, "item": item}

    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body, default=str),
    }
