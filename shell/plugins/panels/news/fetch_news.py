#!/usr/bin/python3
"""Fetch and normalize the fixed official Omarchy RSS feed."""

from __future__ import annotations

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
        if self.parts and self.parts[-1] != "<br><br>":
            self.parts.append("<br><br>")

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
        return "".join(self.parts).strip().removeprefix("<br><br>").removesuffix("<br><br>")


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


def cache_path() -> Path:
    return state_dir() / "feed.json"


def clean_text(value: str | None, limit: int) -> str:
    text = " ".join((value or "").split())
    return text[:limit]


def canonical_news_url(value: str | None) -> str:
    url = clean_text(value, 2048)
    parsed = urlparse(url)
    if parsed.scheme != "https" or parsed.netloc != "omarchy.org":
        return ""
    if not parsed.path.startswith("/news/"):
        return ""
    return parsed._replace(params="", query="", fragment="").geturl()


def parse_feed(payload: bytes) -> list[dict[str, str]]:
    root = ET.fromstring(payload)
    channel = root.find("channel")
    if channel is None:
        raise ValueError("RSS channel is missing")

    items: list[dict[str, str]] = []
    creator_tag = "{http://purl.org/dc/elements/1.1/}creator"
    content_tag = "{http://purl.org/rss/1.0/modules/content/}encoded"
    for node in channel.findall("item")[:MAX_ITEMS]:
        link = canonical_news_url(node.findtext("link"))
        title = clean_text(node.findtext("title"), 240)
        if not link or not title:
            continue
        guid = canonical_news_url(node.findtext("guid")) or link
        summary = article_text(element_text(node.find("description")), 500)
        raw_content = node.findtext(content_tag)
        content = article_text(raw_content) or summary
        content_html = article_markup(raw_content) if raw_content else ""
        items.append(
            {
                "id": guid,
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


def fetch() -> bytes:
    request = urllib.request.Request(
        FEED_URL,
        headers={"Accept": "application/rss+xml, application/xml", "User-Agent": USER_AGENT},
    )
    context = ssl.create_default_context(cafile=SYSTEM_CA_BUNDLE)
    opener = urllib.request.build_opener(
        urllib.request.ProxyHandler({}),
        urllib.request.HTTPSHandler(context=context),
    )
    with opener.open(request, timeout=8) as response:
        if response.geturl() != FEED_URL:
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


def cached_result(error: str) -> dict[str, object] | None:
    try:
        cached = json.loads(cache_path().read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None
    if not isinstance(cached, dict) or not isinstance(cached.get("items"), list):
        return None
    cached["ok"] = True
    cached["stale"] = True
    cached["error"] = clean_text(error, 180)
    return cached


def main() -> int:
    try:
        result: dict[str, object] = {
            "ok": True,
            "stale": False,
            "error": "",
            "fetchedAt": datetime.now(timezone.utc).isoformat(),
            "items": parse_feed(fetch()),
        }
        atomic_write(cache_path(), result)
    except (OSError, ValueError, ET.ParseError) as exc:
        result = cached_result(str(exc))
        if result is None:
            print(clean_text(str(exc), 180), file=sys.stderr)
            return 1

    json.dump(result, sys.stdout, ensure_ascii=False, separators=(",", ":"))
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
