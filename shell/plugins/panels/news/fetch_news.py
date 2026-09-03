#!/usr/bin/python3
"""Fetch and normalize the fixed publisher feeds enabled for Omarchy News."""

from __future__ import annotations

import argparse
import json
import os
import ssl
import sys
import tempfile
import urllib.request
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from html import escape
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlparse

FEED_URL = "https://omarchy.org/news/rss.xml"
MAX_RESPONSE_BYTES = 1024 * 1024
MAX_ITEMS = 40
USER_AGENT = "Omarchy-News-Panel/1.0"
SYSTEM_CA_BUNDLE = "/etc/ssl/certs/ca-certificates.crt"
MAX_ARTICLE_CHARS = 12_000

SOURCE_CATALOG = {
    "omarchy": {
        "id": "omarchy",
        "name": "Omarchy",
        "url": FEED_URL,
        "article_hosts": ("omarchy.org",),
        "article_path_prefix": "/news/",
    },
    "bbc-news": {
        "id": "bbc-news",
        "name": "BBC News",
        "url": "https://feeds.bbci.co.uk/news/rss.xml",
        "article_hosts": ("bbc.co.uk", "bbc.com"),
        "article_path_prefix": "/",
    },
}


class ArticleTextParser(HTMLParser):
    """Turn trusted-feed markup into readable text without rendering HTML."""

    block_tags = {"article", "blockquote", "br", "div", "h1", "h2", "h3", "h4", "li", "p", "pre"}

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.parts: list[str] = []

    def newline(self) -> None:
        if self.parts and self.parts[-1] != "\n":
            self.parts.append("\n")

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag in self.block_tags:
            self.newline()
        if tag == "li":
            self.parts.append("• ")

    def handle_endtag(self, tag: str) -> None:
        if tag in self.block_tags:
            self.newline()

    def handle_data(self, data: str) -> None:
        self.parts.append(data)


class ArticleMarkupParser(HTMLParser):
    """Keep readable spacing and safe HTTP links; discard active markup."""

    block_tags = {"article", "blockquote", "br", "div", "h1", "h2", "h3", "h4", "li", "p", "pre"}
    skipped_tags = {"script", "style"}

    def __init__(self, limit: int) -> None:
        super().__init__(convert_charrefs=True)
        self.limit = limit
        self.visible_chars = 0
        self.parts: list[str] = []
        self.link_stack: list[bool] = []
        self.skip_depth = 0

    def newline(self) -> None:
        if self.parts and self.parts[-1] != "<br>":
            self.parts.append("<br>")

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        tag = tag.lower()
        if tag in self.skipped_tags:
            self.skip_depth += 1
            return
        if self.skip_depth:
            return
        if tag in self.block_tags:
            self.newline()
        if tag == "li":
            self.parts.append("• ")
        if tag == "a":
            href = next((value for name, value in attrs if name.lower() == "href"), None)
            safe_href = external_url(href)
            self.link_stack.append(bool(safe_href))
            if safe_href:
                self.parts.append(f'<a href="{escape(safe_href, quote=True)}">')

    def handle_endtag(self, tag: str) -> None:
        tag = tag.lower()
        if tag in self.skipped_tags:
            self.skip_depth = max(0, self.skip_depth - 1)
            return
        if self.skip_depth:
            return
        if tag == "a" and self.link_stack:
            if self.link_stack.pop():
                self.parts.append("</a>")
        if tag in self.block_tags:
            self.newline()

    def handle_data(self, data: str) -> None:
        if self.skip_depth or self.visible_chars >= self.limit:
            return
        remaining = self.limit - self.visible_chars
        value = data[:remaining]
        self.visible_chars += len(value)
        self.parts.append(escape(value))

    def markup(self) -> str:
        while self.link_stack:
            if self.link_stack.pop():
                self.parts.append("</a>")
        return "".join(self.parts).strip().removeprefix("<br>").removesuffix("<br>")


def article_text(value: str | None, limit: int = MAX_ARTICLE_CHARS) -> str:
    parser = ArticleTextParser()
    parser.feed(value or "")
    parser.close()
    lines = [" ".join(line.split()) for line in "".join(parser.parts).splitlines()]
    paragraphs = [line for line in lines if line]
    return "\n\n".join(paragraphs)[:limit]


def external_url(value: str | None) -> str:
    url = clean_text(value, 2048)
    parsed = urlparse(url)
    return url if parsed.scheme in {"http", "https"} and parsed.netloc else ""


def article_markup(value: str | None, limit: int = MAX_ARTICLE_CHARS) -> str:
    parser = ArticleMarkupParser(limit)
    parser.feed(value or "")
    parser.close()
    return parser.markup()


def element_text(node: ET.Element | None) -> str:
    return "" if node is None else "".join(node.itertext())


def state_dir() -> Path:
    root = os.environ.get("XDG_STATE_HOME")
    if root:
        return Path(root) / "omarchy" / "news"
    return Path.home() / ".local" / "state" / "omarchy" / "news"


def cache_path(source_id: str = "omarchy") -> Path:
    suffix = "feed.json" if source_id == "omarchy" else f"feed-{source_id}.json"
    return state_dir() / suffix


def clean_text(value: str | None, limit: int) -> str:
    text = " ".join((value or "").split())
    return text[:limit]


def host_matches(host: str, allowed_hosts: tuple[str, ...]) -> bool:
    return any(host == allowed or host.endswith(f".{allowed}") for allowed in allowed_hosts)


def source_article_url(value: str | None, source: dict[str, object]) -> str:
    url = clean_text(value, 2048)
    parsed = urlparse(url)
    host = (parsed.hostname or "").lower()
    allowed_hosts = tuple(str(host) for host in source["article_hosts"])
    if parsed.scheme != "https" or not host_matches(host, allowed_hosts):
        return ""
    try:
        port = parsed.port
    except ValueError:
        return ""
    if parsed.username or parsed.password or port not in (None, 443):
        return ""
    if not parsed.path.startswith(str(source["article_path_prefix"])):
        return ""
    return parsed._replace(netloc=host, params="", query="", fragment="").geturl()


def canonical_news_url(value: str | None) -> str:
    return source_article_url(value, SOURCE_CATALOG["omarchy"])


def parse_feed(payload: bytes, source: dict[str, object] | None = None) -> list[dict[str, str]]:
    source = source or SOURCE_CATALOG["omarchy"]
    root = ET.fromstring(payload)
    channel = root.find("channel")
    if channel is None:
        raise ValueError("RSS channel is missing")

    items: list[dict[str, str]] = []
    creator_tag = "{http://purl.org/dc/elements/1.1/}creator"
    content_tag = "{http://purl.org/rss/1.0/modules/content/}encoded"
    for node in channel.findall("item")[:MAX_ITEMS]:
        link = source_article_url(node.findtext("link"), source)
        title = clean_text(node.findtext("title"), 240)
        if not link or not title:
            continue
        guid = source_article_url(node.findtext("guid"), source) or link
        summary = article_text(element_text(node.find("description")), 500)
        raw_content = node.findtext(content_tag)
        content = article_text(raw_content) or summary
        content_html = article_markup(raw_content) if raw_content else ""
        items.append(
            {
                "id": f'{source["id"]}:{guid}',
                "sourceId": str(source["id"]),
                "sourceName": str(source["name"]),
                "sourceUrl": str(source["url"]),
                "title": title,
                "url": link,
                "summary": summary,
                "content": content,
                "contentHtml": content_html,
                "author": clean_text(node.findtext(creator_tag), 80),
                "published": clean_text(node.findtext("pubDate"), 100),
            }
        )
    return items


def fetch(source: dict[str, object] | None = None) -> bytes:
    source = source or SOURCE_CATALOG["omarchy"]
    feed_url = str(source["url"])
    request = urllib.request.Request(
        feed_url,
        headers={"Accept": "application/rss+xml, application/xml", "User-Agent": USER_AGENT},
    )
    context = ssl.create_default_context(cafile=SYSTEM_CA_BUNDLE)
    opener = urllib.request.build_opener(
        urllib.request.ProxyHandler({}),
        urllib.request.HTTPSHandler(context=context),
    )
    with opener.open(request, timeout=8) as response:
        if response.geturl() != feed_url:
            raise ValueError("feed redirected away from its canonical URL")
        payload = response.read(MAX_RESPONSE_BYTES + 1)
    if len(payload) > MAX_RESPONSE_BYTES:
        raise ValueError("feed exceeds the 1 MiB limit")
    return payload


def atomic_write(path: Path, data: dict[str, object]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=".feed-", suffix=".json", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(data, handle, ensure_ascii=False, separators=(",", ":"))
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, path)
    finally:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass


def cached_result(source: dict[str, object], error: str) -> dict[str, object] | None:
    try:
        cached = json.loads(cache_path(str(source["id"])).read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None
    if not isinstance(cached, dict) or not isinstance(cached.get("items"), list):
        return None
    cached["stale"] = True
    cached["error"] = clean_text(error, 180)
    for item in cached["items"]:
        if not isinstance(item, dict):
            continue
        item["sourceId"] = str(source["id"])
        item["sourceName"] = str(source["name"])
        item["sourceUrl"] = str(source["url"])
        item_id = str(item.get("id", ""))
        if item_id and not item_id.startswith(f'{source["id"]}:'):
            item["id"] = f'{source["id"]}:{item_id}'
    return cached


def selected_sources(value: str) -> list[dict[str, object]]:
    requested = [part.strip() for part in value.split(",") if part.strip()]
    ids = ["omarchy", *requested]
    seen: set[str] = set()
    sources: list[dict[str, object]] = []
    for source_id in ids:
        if source_id in seen or source_id not in SOURCE_CATALOG:
            continue
        seen.add(source_id)
        sources.append(SOURCE_CATALOG[source_id])
    return sources


def published_key(item: dict[str, str]) -> float:
    try:
        from email.utils import parsedate_to_datetime

        return parsedate_to_datetime(item.get("published", "")).timestamp()
    except (AttributeError, TypeError, ValueError, OverflowError):
        return 0.0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--sources", default="omarchy")
    args = parser.parse_args(argv)

    items: list[dict[str, str]] = []
    source_states: list[dict[str, object]] = []
    errors: list[str] = []
    fetched_at = datetime.now(timezone.utc).isoformat()

    for source in selected_sources(args.sources):
        error = ""
        stale = False
        try:
            source_items = parse_feed(fetch(source), source)
            atomic_write(
                cache_path(str(source["id"])),
                {"fetchedAt": fetched_at, "items": source_items},
            )
        except (OSError, ValueError, ET.ParseError) as exc:
            error = clean_text(str(exc), 180)
            cached = cached_result(source, error)
            source_items = [] if cached is None else list(cached["items"])
            stale = cached is not None
            errors.append(f'{source["name"]}: {error}')

        items.extend(item for item in source_items if isinstance(item, dict))
        source_states.append(
            {
                "id": source["id"],
                "name": source["name"],
                "url": source["url"],
                "stale": stale,
                "error": error,
                "itemCount": len(source_items),
            }
        )

    if not items and errors:
        print(clean_text("; ".join(errors), 180), file=sys.stderr)
        return 1

    items.sort(key=published_key, reverse=True)
    result: dict[str, object] = {
        "ok": True,
        "stale": any(bool(source["stale"]) for source in source_states),
        "partial": bool(errors),
        "error": clean_text("; ".join(errors), 180),
        "fetchedAt": fetched_at,
        "sources": source_states,
        "items": items,
    }

    json.dump(result, sys.stdout, ensure_ascii=False, separators=(",", ":"))
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
