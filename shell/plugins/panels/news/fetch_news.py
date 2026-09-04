#!/usr/bin/python3
"""Fetch and normalize the fixed publisher feeds enabled for Omarchy News."""

from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import ipaddress
import json
import os
import socket
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
        "category": "official",
        "url": FEED_URL,
        "article_hosts": ("omarchy.org",),
        "article_path_prefix": "/news/",
    },
    "hacker-news": {
        "id": "hacker-news",
        "name": "Hacker News",
        "category": "developer",
        "url": "https://news.ycombinator.com/rss",
        "article_hosts": (),
        "allow_external_articles": True,
        "article_path_prefix": "/",
    },
    "ars-technica": {
        "id": "ars-technica",
        "name": "Ars Technica",
        "category": "technology",
        "url": "https://feeds.arstechnica.com/arstechnica/index",
        "article_hosts": ("arstechnica.com",),
        "article_path_prefix": "/",
    },
    "techcrunch": {
        "id": "techcrunch",
        "name": "TechCrunch",
        "category": "startup",
        "url": "https://techcrunch.com/feed/",
        "article_hosts": ("techcrunch.com",),
        "article_path_prefix": "/",
    },
    "the-verge": {
        "id": "the-verge",
        "name": "The Verge",
        "category": "technology",
        "url": "https://www.theverge.com/rss/index.xml",
        "article_hosts": ("theverge.com",),
        "article_path_prefix": "/",
    },
    "wired": {
        "id": "wired",
        "name": "WIRED",
        "category": "technology",
        "url": "https://www.wired.com/feed/rss",
        "article_hosts": ("wired.com",),
        "article_path_prefix": "/",
    },
    "phoronix": {
        "id": "phoronix",
        "name": "Phoronix",
        "category": "linux",
        "url": "https://www.phoronix.com/rss.php",
        "article_hosts": ("phoronix.com",),
        "article_path_prefix": "/",
    },
    "its-foss": {
        "id": "its-foss",
        "name": "It's FOSS",
        "category": "linux",
        "url": "https://itsfoss.com/rss/",
        "article_hosts": ("itsfoss.com",),
        "article_path_prefix": "/",
    },
    "openai-news": {
        "id": "openai-news",
        "name": "OpenAI News",
        "category": "ai",
        "url": "https://openai.com/news/rss.xml",
        "article_hosts": ("openai.com",),
        "article_path_prefix": "/",
    },
    "hugging-face": {
        "id": "hugging-face",
        "name": "Hugging Face",
        "category": "ai",
        "url": "https://huggingface.co/blog/feed.xml",
        "article_hosts": ("huggingface.co",),
        "article_path_prefix": "/blog/",
    },
    "mit-ai": {
        "id": "mit-ai",
        "name": "MIT News: AI",
        "category": "ai",
        "url": "https://news.mit.edu/rss/topic/artificial-intelligence2",
        "article_hosts": ("news.mit.edu",),
        "article_path_prefix": "/",
    },
}

TECH_FEED_IDS = (
    "hacker-news",
    "ars-technica",
    "techcrunch",
    "the-verge",
    "wired",
    "phoronix",
    "its-foss",
    "openai-news",
    "hugging-face",
    "mit-ai",
)
MAX_CUSTOM_FEEDS = 10
MAX_CUSTOM_FEEDS_SETTING_CHARS = 4096


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
    try:
        parsed.port
    except ValueError:
        return ""
    if parsed.scheme not in {"http", "https"} or not parsed.hostname:
        return ""
    if parsed.username or parsed.password:
        return ""
    return url


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
    allow_external = source.get("allow_external_articles") is True
    allowed_hosts = tuple(str(host) for host in source["article_hosts"])
    allowed_schemes = {"http", "https"} if allow_external else {"https"}
    if parsed.scheme not in allowed_schemes or not host:
        return ""
    if not allow_external and not host_matches(host, allowed_hosts):
        return ""
    try:
        port = parsed.port
    except ValueError:
        return ""
    default_port = 80 if parsed.scheme == "http" else 443
    if parsed.username or parsed.password or port not in (None, default_port):
        return ""
    if not parsed.path.startswith(str(source["article_path_prefix"])):
        return ""
    query = parsed.query if allow_external else ""
    return parsed._replace(netloc=host, params="", query=query, fragment="").geturl()


def canonical_feed_url(value: str | None) -> str:
    url = clean_text(value, 2048)
    parsed = urlparse(url)
    host = (parsed.hostname or "").lower()
    try:
        port = parsed.port
    except ValueError:
        return ""
    try:
        literal_ip = ipaddress.ip_address(host)
    except ValueError:
        literal_ip = None
    if parsed.scheme != "https" or not host or parsed.username or parsed.password:
        return ""
    if port not in (None, 443) or literal_ip is not None:
        return ""
    if host == "localhost" or host.endswith(".localhost") or host.endswith(".local"):
        return ""
    return parsed._replace(netloc=host, params="", fragment="").geturl()


def custom_source(raw_url: str, name: str = "") -> dict[str, object]:
    url = canonical_feed_url(raw_url)
    if not url:
        raise ValueError("Feed must be a public HTTPS URL")
    host = (urlparse(url).hostname or "").lower()
    return {
        "id": "custom-" + hashlib.sha256(url.encode("utf-8")).hexdigest()[:12],
        "name": clean_text(name, 48) or host,
        "category": "custom",
        "url": url,
        "article_hosts": (),
        "allow_external_articles": True,
        "article_path_prefix": "/",
        "custom": True,
    }


def parse_custom_sources(value: str) -> tuple[list[dict[str, object]], list[str]]:
    entries = value[:MAX_CUSTOM_FEEDS_SETTING_CHARS].replace("\n", ";").split(";")
    sources: list[dict[str, object]] = []
    errors: list[str] = []
    seen: set[str] = set()
    for index, entry in enumerate(entries):
        raw = entry.strip()
        if not raw:
            continue
        name, separator, raw_url = raw.partition("|")
        if not separator:
            raw_url = name
            name = ""
        try:
            source = custom_source(raw_url, name)
        except ValueError:
            errors.append(f"Custom feed {index + 1} must be a public HTTPS URL")
            continue
        url = str(source["url"])
        if url in seen:
            continue
        seen.add(url)
        sources.append(source)
        if len(sources) >= MAX_CUSTOM_FEEDS:
            if any(remaining.strip() for remaining in entries[index + 1 :]):
                errors.append(f"Custom feeds are limited to {MAX_CUSTOM_FEEDS}")
            break
    return sources, errors


def custom_sources(value: str) -> list[dict[str, object]]:
    return parse_custom_sources(value)[0]


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
                "sourceCategory": str(source["category"]),
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


def inspect_custom_feed(raw_url: str, requested_name: str = "") -> dict[str, str]:
    source = custom_source(raw_url, requested_name)
    payload = fetch(source)
    root = ET.fromstring(payload)
    channel = root.find("channel")
    if channel is None:
        raise ValueError("RSS channel is missing")

    discovered_name = clean_text(channel.findtext("title"), 48)
    return {
        "name": clean_text(requested_name, 48)
        or discovered_name
        or str(source["name"]),
        "url": str(source["url"]),
    }


def fetch(source: dict[str, object] | None = None) -> bytes:
    source = source or SOURCE_CATALOG["omarchy"]
    feed_url = str(source["url"])
    if source.get("custom") is True:
        host = urlparse(feed_url).hostname or ""
        addresses = socket.getaddrinfo(host, 443, type=socket.SOCK_STREAM)
        if not addresses:
            raise ValueError("custom feed host could not be resolved")
        for address in addresses:
            ip = ipaddress.ip_address(address[4][0])
            if not ip.is_global:
                raise ValueError("custom feed host does not resolve to a public address")
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
        item["sourceCategory"] = str(source["category"])
        item["sourceUrl"] = str(source["url"])
        item_id = str(item.get("id", ""))
        if item_id and not item_id.startswith(f'{source["id"]}:'):
            item["id"] = f'{source["id"]}:{item_id}'
    return cached


def selected_sources(value: str, custom_value: str = "") -> list[dict[str, object]]:
    requested = [part.strip() for part in value.split(",") if part.strip()]
    ids = ["omarchy", *requested]
    seen: set[str] = set()
    sources: list[dict[str, object]] = []
    for source_id in ids:
        if source_id in seen or source_id not in SOURCE_CATALOG:
            continue
        seen.add(source_id)
        sources.append(SOURCE_CATALOG[source_id])
    for source in custom_sources(custom_value):
        if str(source["id"]) in seen:
            continue
        seen.add(str(source["id"]))
        sources.append(source)
    return sources


def published_key(item: dict[str, str]) -> float:
    try:
        from email.utils import parsedate_to_datetime

        return parsedate_to_datetime(item.get("published", "")).timestamp()
    except (AttributeError, TypeError, ValueError, OverflowError):
        return 0.0


def load_source(
    source: dict[str, object], fetched_at: str
) -> tuple[list[dict[str, str]], dict[str, object], str]:
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
        source_items = [] if cached is None else [
            item for item in cached["items"] if isinstance(item, dict)
        ]
        stale = cached is not None

    state: dict[str, object] = {
        "id": source["id"],
        "name": source["name"],
        "category": source["category"],
        "url": source["url"],
        "stale": stale,
        "error": error,
        "itemCount": len(source_items),
    }
    return source_items, state, error


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--sources", default="omarchy")
    parser.add_argument("--custom-feeds", default="")
    parser.add_argument("--inspect-feed", default="")
    parser.add_argument("--inspect-name", default="")
    args = parser.parse_args(argv)

    if args.inspect_feed:
        try:
            inspected = inspect_custom_feed(args.inspect_feed, args.inspect_name)
        except (OSError, ValueError, ET.ParseError) as exc:
            print(clean_text(str(exc), 180), file=sys.stderr)
            return 1
        json.dump({"ok": True, **inspected}, sys.stdout, ensure_ascii=False, separators=(",", ":"))
        sys.stdout.write("\n")
        return 0

    items: list[dict[str, str]] = []
    source_states: list[dict[str, object]] = []
    _, configuration_errors = parse_custom_sources(args.custom_feeds)
    errors: list[str] = list(configuration_errors)
    fetched_at = datetime.now(timezone.utc).isoformat()

    sources = selected_sources(args.sources, args.custom_feeds)
    with ThreadPoolExecutor(max_workers=min(4, len(sources))) as executor:
        loaded_sources = executor.map(lambda source: load_source(source, fetched_at), sources)
        for source, (source_items, state, error) in zip(sources, loaded_sources):
            items.extend(source_items)
            source_states.append(state)
            if error:
                errors.append(f'{source["name"]}: {error}')

    if not items and errors:
        print(clean_text("; ".join(errors), 180), file=sys.stderr)
        return 1

    items.sort(key=published_key, reverse=True)
    result: dict[str, object] = {
        "ok": True,
        "stale": any(bool(source["stale"]) for source in source_states),
        "partial": bool(errors),
        "configurationError": clean_text("; ".join(configuration_errors), 180),
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
