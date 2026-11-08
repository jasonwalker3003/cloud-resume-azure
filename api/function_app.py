import datetime as dt
import json
import logging
import os
import uuid

import azure.functions as func
from azure.cosmos import CosmosClient
from azure.identity import DefaultAzureCredential

from logic import check_site, increment_counter, uptime_summary

app = func.FunctionApp(http_auth_level=func.AuthLevel.ANONYMOUS)
_db = None


def database():
    """One Cosmos client per instance, signed in with the app's managed identity (no keys)."""
    global _db
    if _db is None:
        client = CosmosClient(os.environ["COSMOS_ENDPOINT"], credential=DefaultAzureCredential())
        _db = client.get_database_client(os.environ["COSMOS_DATABASE"])
    return _db


def json_response(body, status=200):
    return func.HttpResponse(json.dumps(body), status_code=status, mimetype="application/json")


@app.route(route="visitors", methods=["POST"])
def visitors(req: func.HttpRequest) -> func.HttpResponse:
    count = increment_counter(database().get_container_client("counter"))
    return json_response({"count": count})


@app.route(route="status", methods=["GET"])
def status(req: func.HttpRequest) -> func.HttpResponse:
    since = (dt.datetime.now(dt.timezone.utc) - dt.timedelta(days=30)).isoformat()
    records = list(database().get_container_client("uptime").query_items(
        query="SELECT c.ok, c.ms FROM c WHERE c.ts >= @since",
        parameters=[{"name": "@since", "value": since}],
        enable_cross_partition_query=True,
    ))
    return json_response(uptime_summary(records))


@app.timer_trigger(schedule="0 */5 * * * *", arg_name="timer", run_on_startup=False)
def uptime_check(timer: func.TimerRequest) -> None:
    result = check_site(os.environ["SITE_URL"], os.environ["EXPECTED_TEXT"])
    now = dt.datetime.now(dt.timezone.utc)
    record = {"id": str(uuid.uuid4()), "day": now.date().isoformat(), "ts": now.isoformat(), **result}
    database().get_container_client("uptime").create_item(record)
    if not result["ok"]:
        # An unhandled error is recorded in Application Insights, and that fires the email alert.
        raise RuntimeError(f"Uptime check failed for {os.environ['SITE_URL']}: {result['error']}")
    logging.info("Uptime check passed in %s ms", result["ms"])
