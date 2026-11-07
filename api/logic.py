"""Plain-Python logic, kept apart from Azure Functions so it can be unit tested."""
import time
import urllib.error
import urllib.request

from azure.cosmos.exceptions import CosmosResourceExistsError, CosmosResourceNotFoundError

COUNTER_ID = "visitors"
INCREMENT = [{"op": "incr", "path": "/count", "value": 1}]


def increment_counter(container, item_id=COUNTER_ID):
    """Add 1 to the visitor count and return the new total."""
    try:
        # A patch is atomic: two visitors at the same moment can't overwrite each other.
        item = container.patch_item(item=item_id, partition_key=item_id, patch_operations=INCREMENT)
    except CosmosResourceNotFoundError:
        try:
            item = container.create_item({"id": item_id, "count": 1})
        except CosmosResourceExistsError:  # another visitor created it a moment ago
            item = container.patch_item(item=item_id, partition_key=item_id, patch_operations=INCREMENT)
    return item["count"]


def _fetch(url, timeout):
    req = urllib.request.Request(url, headers={"User-Agent": "resume-uptime-monitor"})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return resp.status, resp.read().decode("utf-8", errors="replace")


def check_site(url, expected_text, fetch=_fetch, timeout=10, slow_ms=3000):
    """The three checks: does it load, is it fast enough, is the right content there."""
    start = time.perf_counter()
    try:
        status, body = fetch(url, timeout)
    except urllib.error.HTTPError as err:  # the server answered with an error code
        ms = round((time.perf_counter() - start) * 1000)
        return {"ok": False, "status": err.code, "ms": ms, "error": f"HTTP {err.code}"}
    except (urllib.error.URLError, TimeoutError, OSError) as err:  # no answer at all
        return {"ok": False, "status": None, "ms": None, "error": f"unreachable: {err}"}
    ms = round((time.perf_counter() - start) * 1000)
    if status != 200:
        return {"ok": False, "status": status, "ms": ms, "error": f"HTTP {status}"}
    if expected_text not in body:
        return {"ok": False, "status": status, "ms": ms, "error": "expected content missing"}
    if ms > slow_ms:
        return {"ok": False, "status": status, "ms": ms, "error": f"slow: {ms} ms"}
    return {"ok": True, "status": status, "ms": ms, "error": None}


def uptime_summary(records):
    """Turn stored check results into the numbers shown on the site."""
    if not records:
        return {"checks": 0, "uptime_percent": None, "avg_ms": None}
    passed = [r for r in records if r.get("ok")]
    timed = [r["ms"] for r in records if r.get("ms") is not None]
    return {
        "checks": len(records),
        "uptime_percent": round(100 * len(passed) / len(records), 2),
        "avg_ms": round(sum(timed) / len(timed)) if timed else None,
    }
