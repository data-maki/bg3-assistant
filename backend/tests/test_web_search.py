"""Hermetic tests for the Exa search client (no real network calls)."""

from app import web_search


class _FakeResponse:
    def __init__(self, payload: dict) -> None:
        self._payload = payload

    def raise_for_status(self) -> None:
        pass

    def json(self) -> dict:
        return self._payload


def test_search_maps_results_to_sources(monkeypatch) -> None:
    captured = {}

    def fake_post(url, headers, json, timeout):  # noqa: A002 - mirror httpx.post signature
        captured["url"], captured["headers"], captured["json"] = url, headers, json
        return _FakeResponse(
            {
                "results": [
                    {"title": "Nere - bg3.wiki", "url": "https://bg3.wiki/wiki/Nere", "text": "True Soul Nere is..."},
                    {"title": None, "url": "https://example.com/guide"},
                ]
            }
        )

    monkeypatch.setattr(web_search.httpx, "post", fake_post)
    sources = web_search.search("bg3 nere", "exa-test")

    assert captured["url"] == web_search.EXA_SEARCH_URL
    assert captured["headers"]["x-api-key"] == "exa-test"
    assert captured["json"]["query"] == "bg3 nere"
    assert sources[0].title == "Nere - bg3.wiki"
    assert sources[0].snippet.startswith("True Soul Nere")
    assert sources[1].title == "https://example.com/guide"  # falls back to the URL


def test_search_without_key_or_query_is_a_noop(monkeypatch) -> None:
    def boom(*args, **kwargs):
        raise AssertionError("must not call the network")

    monkeypatch.setattr(web_search.httpx, "post", boom)
    assert web_search.search("bg3 nere", "") == []
    assert web_search.search("   ", "exa-test") == []


def test_search_failure_returns_empty(monkeypatch) -> None:
    def boom(*args, **kwargs):
        raise RuntimeError("network down")

    monkeypatch.setattr(web_search.httpx, "post", boom)
    assert web_search.search("bg3 nere", "exa-test") == []
