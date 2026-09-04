#!/usr/bin/python3
"""Fetch and normalize publisher feeds enabled in Omarchy RSS Reader."""

from __future__ import annotations

import argparse
import copy
from concurrent.futures import ThreadPoolExecutor, as_completed
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
from urllib.parse import urljoin, urlparse

FEED_URL = "https://omarchy.org/news/rss.xml"
MAX_RESPONSE_BYTES = 1024 * 1024
MAX_REDIRECTS = 3
MAX_ITEMS = 40
DEFAULT_ITEM_LIMIT = 10
USER_AGENT = "Omarchy-RSS-Reader/1.0"
SYSTEM_CA_BUNDLE = "/etc/ssl/certs/ca-certificates.crt"
MAX_ARTICLE_CHARS = 12_000
SSL_CONTEXT = ssl.create_default_context(cafile=SYSTEM_CA_BUNDLE)

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

    def __init__(self, limit: int, base_url: str = "") -> None:
        super().__init__(convert_charrefs=True)
        self.base_url = base_url
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
            safe_href = external_url(urljoin(self.base_url, href or "")) if href else ""
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


def article_markup(value: str | None, limit: int = MAX_ARTICLE_CHARS, base_url: str = "") -> str:
    parser = ArticleMarkupParser(limit, base_url)
    parser.feed(value or "")
    parser.close()
    return parser.markup()


def element_text(node: ET.Element | None) -> str:
    return "" if node is None else "".join(node.itertext())


def local_name(tag: str) -> str:
    return tag.rsplit("}", 1)[-1]


def child(node: ET.Element, name: str) -> ET.Element | None:
    return next((candidate for candidate in node if local_name(candidate.tag) == name), None)


def children(node: ET.Element, name: str) -> list[ET.Element]:
    return [candidate for candidate in node if local_name(candidate.tag) == name]


def child_text(node: ET.Element, name: str) -> str:
    return element_text(child(node, name))


def element_markup(node: ET.Element | None) -> str:
    if node is None:
        return ""
    if len(node) == 0:
        return node.text or ""
    parts = [node.text or ""]
    for nested in node:
        parts.append(ET.tostring(nested, encoding="unicode", method="html"))
    return "".join(parts)


def atom_markup(node: ET.Element | None, base_url: str) -> tuple[str, str]:
    if node is None:
        return "", base_url
    base_url = urljoin(base_url, node.get("{http://www.w3.org/XML/1998/namespace}base", ""))
    kind = node.get("type", "text")
    if kind in {"text", "text/plain"}:
        return escape(element_text(node)), base_url
    if kind in {"html", "text/html"}:
        return node.text or "", base_url
    if kind != "xhtml":
        return "", base_url
    node = copy.deepcopy(node)

    def normalize(element: ET.Element, base: str) -> None:
        base = urljoin(base, element.get("{http://www.w3.org/XML/1998/namespace}base", ""))
        element.tag = local_name(element.tag)
        if "href" in element.attrib:
            element.set("href", urljoin(base, element.get("href", "")))
        for nested in element:
            normalize(nested, base)

    for nested in node:
        normalize(nested, base_url)
    return element_markup(node), base_url


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
        "user_named": bool(clean_text(name, 48)),
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


def parse_feed(
    payload: bytes,
    source: dict[str, object] | None = None,
    item_limit: int = MAX_ITEMS,
) -> list[dict[str, str]]:
    source = source or SOURCE_CATALOG["omarchy"]
    root = ET.fromstring(payload)
    items: list[dict[str, str]] = []
    creator_tag = "{http://purl.org/dc/elements/1.1/}creator"
    content_tag = "{http://purl.org/rss/1.0/modules/content/}encoded"
    limit = max(1, min(MAX_ITEMS, item_limit))
    is_atom = local_name(root.tag) == "feed"
    if is_atom:
        nodes = children(root, "entry")
    else:
        channel = child(root, "channel")
        if channel is None:
            raise ValueError("RSS or Atom feed is missing its item container")
        nodes = children(channel, "item")

    seen = set()
    for node in nodes:
        body_base = str(source["url"])
        if is_atom:
            xml_base = "{http://www.w3.org/XML/1998/namespace}base"
            entry_base = urljoin(urljoin(str(source["url"]), root.get(xml_base, "")), node.get(xml_base, ""))
            atom_links = children(node, "link")
            author_node = child(node, "author")
            raw_link = next(
                (
                    urljoin(urljoin(entry_base, candidate.get(xml_base, "")), candidate.get("href", ""))
                    for candidate in atom_links
                    if candidate.get("rel", "alternate") in {"", "alternate"}
                ),
                "",
            )
            raw_summary, summary_base = atom_markup(child(node, "summary"), entry_base)
            raw_content, content_base = atom_markup(child(node, "content"), entry_base)
            body_base = content_base if raw_content else summary_base
            raw_author = child_text(author_node, "name") if author_node is not None else ""
            raw_published = child_text(node, "published") or child_text(node, "updated")
            raw_guid = child_text(node, "id")
        else:
            raw_link = child_text(node, "link")
            raw_summary = element_markup(child(node, "description"))
            raw_content = node.findtext(content_tag) or ""
            raw_author = node.findtext(creator_tag) or child_text(node, "author")
            raw_published = child_text(node, "pubDate")
            raw_guid = child_text(node, "guid")

        link = source_article_url(raw_link, source)
        if not is_atom:
            body_base = link
        title = clean_text(child_text(node, "title"), 240)
        if not link or not title:
            continue
        guid = source_article_url(raw_guid, source) or clean_text(raw_guid, 2048) or link
        if guid in seen:
            continue
        seen.add(guid)
        summary = article_text(raw_summary, 500)
        body = raw_content or raw_summary
        content = article_text(body)
        content_html = article_markup(body, base_url=body_base)
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
                "author": clean_text(raw_author, 80),
                "published": clean_text(raw_published, 100),
            }
        )
        if len(items) >= limit:
            break
    return items


def feed_name(payload: bytes) -> str:
    root = ET.fromstring(payload)
    container = root if local_name(root.tag) == "feed" else child(root, "channel")
    if container is None:
        raise ValueError("RSS or Atom feed is missing its item container")
    return clean_text(child_text(container, "title"), 48)


def inspect_custom_feed(raw_url: str, requested_name: str = "") -> dict[str, str]:
    source = custom_source(raw_url, requested_name)
    payload = fetch(source)
    discovered_name = feed_name(payload)
    return {
        "name": clean_text(requested_name, 48)
        or discovered_name
        or str(source["name"]),
        "url": str(source["url"]),
    }


def require_public_feed_url(value: str) -> str:
    url = canonical_feed_url(value)
    if not url:
        raise ValueError("feed redirect must use a public HTTPS URL")
    host = urlparse(url).hostname or ""
    addresses = socket.getaddrinfo(host, 443, type=socket.SOCK_STREAM)
    if not addresses:
        raise ValueError("custom feed host could not be resolved")
    for address in addresses:
        ip = ipaddress.ip_address(address[4][0])
        if not ip.is_global:
            raise ValueError("custom feed host does not resolve to a public address")
    return url


def safe_redirect_url(source: dict[str, object], current_url: str, target: str) -> str:
    redirected = canonical_feed_url(urljoin(current_url, target))
    if not redirected:
        raise ValueError("feed redirect must use a public HTTPS URL")
    if source.get("custom") is True:
        return require_public_feed_url(redirected)
    original_host = (urlparse(str(source["url"])).hostname or "").removeprefix("www.")
    redirected_host = (urlparse(redirected).hostname or "").removeprefix("www.")
    if redirected_host != original_host:
        raise ValueError("feed redirected away from its publisher")
    return redirected


class SafeRedirectHandler(urllib.request.HTTPRedirectHandler):
    def __init__(self, source: dict[str, object]) -> None:
        super().__init__()
        self.source = source
        self.redirects = 0

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        self.redirects += 1
        if self.redirects > MAX_REDIRECTS:
            raise ValueError(f"feed exceeded {MAX_REDIRECTS} redirects")
        redirected = safe_redirect_url(self.source, req.full_url, newurl)
        return super().redirect_request(req, fp, code, msg, headers, redirected)


def fetch(source: dict[str, object] | None = None) -> bytes:
    source = source or SOURCE_CATALOG["omarchy"]
    feed_url = str(source["url"])
    if source.get("custom") is True:
        require_public_feed_url(feed_url)
    request = urllib.request.Request(
        feed_url,
        headers={
            "Accept": "application/rss+xml, application/atom+xml, application/xml",
            "User-Agent": USER_AGENT,
        },
    )
    opener = urllib.request.build_opener(
        urllib.request.ProxyHandler({}),
        SafeRedirectHandler(source),
        urllib.request.HTTPSHandler(context=SSL_CONTEXT),
    )
    with opener.open(request, timeout=8) as response:
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
        os.replace(temporary, path)
    finally:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass


def cached_result(source: dict[str, object], error: str) -> dict[str, object] | None:
    try:
        cached = json.loads(cache_path(str(source["id"])).read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError):
        return None
    if not isinstance(cached, dict) or not isinstance(cached.get("items"), list):
        return None
    cached["stale"] = True
    cached["error"] = clean_text(error, 180)
    for item in cached["items"]:
        if not isinstance(item, dict):
            continue
        item["sourceId"] = str(source["id"])
        if source.get("user_named") is True or not item.get("sourceName"):
            item["sourceName"] = str(source["name"])
        item["sourceCategory"] = str(source["category"])
        item["sourceUrl"] = str(source["url"])
        item_id = str(item.get("id", ""))
        if item_id and not item_id.startswith(f'{source["id"]}:'):
            item["id"] = f'{source["id"]}:{item_id}'
    return cached


def fresh_cached_items(
    source: dict[str, object], fetched_at: str, max_cache_age: int, item_limit: int
) -> list[dict[str, str]] | None:
    if max_cache_age <= 0:
        return None
    cached = cached_result(source, "")
    if cached is None:
        return None
    try:
        cached_at = datetime.fromisoformat(str(cached.get("fetchedAt", "")))
        now = datetime.fromisoformat(fetched_at)
        if cached_at.tzinfo is None or now.tzinfo is None:
            return None
        age = (now - cached_at).total_seconds()
    except (TypeError, ValueError):
        return None
    if age < 0 or age > max_cache_age:
        return None
    return [item for item in cached["items"] if isinstance(item, dict)][:item_limit]


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
        try:
            return datetime.fromisoformat(item.get("published", "").replace("Z", "+00:00")).timestamp()
        except (AttributeError, TypeError, ValueError, OverflowError):
            return 0.0


def load_source(
    source: dict[str, object],
    fetched_at: str,
    max_cache_age: int = 0,
    item_limit: int = MAX_ITEMS,
) -> tuple[list[dict[str, str]], dict[str, object], str]:
    error = ""
    stale = False
    resolved_source = source
    item_limit = max(1, min(MAX_ITEMS, item_limit))
    source_items = fresh_cached_items(source, fetched_at, max_cache_age, item_limit)
    from_cache = source_items is not None
    if source_items is None:
        try:
            payload = fetch(source)
            if source.get("custom") is True and source.get("user_named") is not True:
                discovered_name = feed_name(payload)
                if discovered_name:
                    resolved_source = {**source, "name": discovered_name}
            source_items = parse_feed(payload, resolved_source, item_limit)
            try:
                atomic_write(
                    cache_path(str(source["id"])),
                    {"fetchedAt": fetched_at, "items": source_items},
                )
            except OSError as exc:
                # Cache persistence is optional; never discard a successful fetch.
                error = clean_text(f"Could not save feed cache: {exc}", 180)
        except (OSError, ValueError, ET.ParseError) as exc:
            error = clean_text(str(exc), 180)
            cached = cached_result(source, error)
            source_items = [] if cached is None else [
                item for item in cached["items"] if isinstance(item, dict)
            ][:item_limit]
            stale = cached is not None

    state: dict[str, object] = {
        "id": source["id"],
        "name": source_items[0].get("sourceName", resolved_source["name"])
        if source_items
        else resolved_source["name"],
        "category": source["category"],
        "url": source["url"],
        "stale": stale,
        "cached": from_cache,
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
    parser.add_argument("--max-cache-age", type=int, default=0)
    parser.add_argument("--item-limit", type=int, default=DEFAULT_ITEM_LIMIT)
    parser.add_argument("--stream", action="store_true")
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

    _, configuration_errors = parse_custom_sources(args.custom_feeds)
    fetched_at = datetime.now(timezone.utc).isoformat()

    sources = selected_sources(args.sources, args.custom_feeds)
    item_limit = max(1, min(MAX_ITEMS, args.item_limit))
    results = {}

    def emit() -> None:
        items = []
        states = []
        errors = list(configuration_errors)
        for source in sources:
            source_items, state, error = results[str(source["id"])]
            items.extend(source_items)
            states.append(state)
            if error:
                errors.append(f'{source["name"]}: {error}')
        items.sort(key=published_key, reverse=True)
        json.dump({
            "ok": True,
            "stale": any(bool(state["stale"]) for state in states),
            "partial": bool(errors),
            "configurationError": clean_text("; ".join(configuration_errors), 180),
            "error": clean_text("; ".join(errors), 180),
            "fetchedAt": fetched_at,
            "sources": states,
            "items": items,
        }, sys.stdout, ensure_ascii=False, separators=(",", ":"))
        sys.stdout.write("\n")
        sys.stdout.flush()

    if args.stream:
        for source in sources:
            cached = cached_result(source, "")
            cached_items = [] if cached is None else [
                item for item in cached["items"] if isinstance(item, dict)
            ][:item_limit]
            results[str(source["id"])] = (cached_items, {
                **{key: source[key] for key in ("id", "name", "category", "url")},
                "stale": bool(cached_items), "cached": cached is not None,
                "error": "", "itemCount": len(cached_items),
            }, "")
        emit()

    with ThreadPoolExecutor(max_workers=min(12, len(sources))) as executor:
        pending = {
            executor.submit(load_source,
                source, fetched_at, max(0, args.max_cache_age), item_limit
            ): source for source in sources
        }
        for future in as_completed(pending):
            source = pending[future]
            results[str(source["id"])] = future.result()
            if args.stream:
                emit()
    if not args.stream:
        emit()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
