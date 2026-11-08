import urllib.error

from azure.cosmos.exceptions import CosmosResourceNotFoundError

from logic import check_site, increment_counter, uptime_summary


class FakeContainer:
    """Stands in for a Cosmos container, so tests need no Azure account."""

    def __init__(self):
        self.items = {}

    def patch_item(self, item, partition_key, patch_operations):
        if item not in self.items:
            raise CosmosResourceNotFoundError(status_code=404, message="not found")
        self.items[item]["count"] += patch_operations[0]["value"]
        return self.items[item]

    def create_item(self, body):
        self.items[body["id"]] = dict(body)
        return self.items[body["id"]]


def test_first_visit_creates_counter():
    assert increment_counter(FakeContainer()) == 1


def test_later_visits_increment():
    container = FakeContainer()
    increment_counter(container)
    increment_counter(container)
    assert increment_counter(container) == 3


def test_site_up_with_right_content():
    result = check_site("https://x", "Jason Walker", fetch=lambda url, t: (200, "<h1>Jason Walker</h1>"))
    assert result["ok"] is True and result["error"] is None


def test_wrong_content_fails():
    result = check_site("https://x", "Jason Walker", fetch=lambda url, t: (200, "Site under maintenance"))
    assert result["ok"] is False and result["error"] == "expected content missing"


def test_unreachable_site_fails():
    def no_answer(url, timeout):
        raise urllib.error.URLError("no route to host")
    result = check_site("https://x", "Jason Walker", fetch=no_answer)
    assert result["ok"] is False and result["error"].startswith("unreachable")


def test_summary_numbers():
    records = [{"ok": True, "ms": 100}, {"ok": True, "ms": 300},
               {"ok": False, "ms": None}, {"ok": True, "ms": 200}]
    assert uptime_summary(records) == {"checks": 4, "uptime_percent": 75.0, "avg_ms": 200}


def test_summary_with_no_checks():
    assert uptime_summary([]) == {"checks": 0, "uptime_percent": None, "avg_ms": None}
