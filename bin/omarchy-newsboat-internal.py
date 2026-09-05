"""Internal data boundary for Omarchy's Newsboat integration.

User-facing commands remain Bash scripts with Omarchy metadata. This module
owns parsing untrusted feeds and subscription files plus the SQLite and JSON
state used by confirmed agent actions.
"""

import argparse
import hashlib
import json
import os
import re
import shlex
import sqlite3
import sys
import time
import xml.etree.ElementTree as ET
import xml.parsers.expat as expat
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import quote, urljoin, urlparse


WEB_URL = re.compile(r"https?://\S+")
EXCERPT_LIMIT = 1500
EDITION_EXCERPT_LIMIT = 24000


class ArticleTextParser(HTMLParser):
    """Extract visible cached text without fetching or executing anything."""

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.hidden = []
        self.parts = []

    def handle_starttag(self, tag, attrs):
        if tag in {"script", "style", "noscript", "template"}:
            self.hidden.append(tag)
        elif tag in {"p", "br", "div", "li", "h1", "h2", "h3"}:
            self.parts.append(" ")

    def handle_endtag(self, tag):
        if self.hidden and tag == self.hidden[-1]:
            self.hidden.pop()
        elif tag in {"p", "div", "li", "h1", "h2", "h3"}:
            self.parts.append(" ")

    def handle_data(self, data):
        if not self.hidden:
            self.parts.append(data)


def article_excerpt(content, limit):
    if limit <= 0:
        return ""
    parser = ArticleTextParser()
    parser.feed(content or "")
    text = clean("".join(parser.parts))
    text = re.sub(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]", "", text)
    return text[:limit]


class NewsboatError(Exception):
    def __init__(self, message, exit_code=1):
        super().__init__(message)
        self.exit_code = exit_code


def clean(value):
    return re.sub(r"\s+", " ", value or "").strip()


def valid_web_url(value):
    parsed = urlparse(value)
    return parsed.scheme in {"http", "https"} and bool(parsed.netloc) and not re.search(r"\s", value)


def print_json(value):
    print(json.dumps(value, ensure_ascii=False, separators=(",", ":")))


def read_json(path):
    with open(path, encoding="utf-8") as source:
        return json.load(source)


def read_subscriptions(path):
    subscriptions = []
    seen = set()
    with open(path, encoding="utf-8") as source:
        for line_number, line in enumerate(source, 1):
            try:
                fields = shlex.split(line, comments=True, posix=True)
            except ValueError as error:
                raise NewsboatError(f"Invalid Newsboat subscriptions at {path}:{line_number}: {error}") from error
            if not fields or not valid_web_url(fields[0]) or fields[0] in seen:
                continue
            seen.add(fields[0])
            subscriptions.append({"url": fields[0], "labels": fields[1:]})
    return subscriptions


def active_feed_urls(path):
    return [subscription["url"] for subscription in read_subscriptions(path)]


def require_fresh_snapshot(snapshot, noun):
    if not isinstance(snapshot, dict) or snapshot.get("version") != 1:
        raise NewsboatError(f"That {noun} is invalid. Run it again.")
    created_at = snapshot.get("created_at")
    if not isinstance(created_at, int):
        raise NewsboatError(f"That {noun} is invalid. Run it again.")
    age = int(time.time()) - created_at
    if age < 0 or age > 86400:
        raise NewsboatError(f"That {noun} has expired. Run it again.")


class DiscoveryParser(HTMLParser):
    def __init__(self, base_url):
        super().__init__(convert_charrefs=True)
        self.base_url = base_url
        self.candidates = []
        self.in_title = False
        self.title_parts = []

    def handle_starttag(self, tag, attrs):
        values = {key.lower(): value for key, value in attrs if key}
        if tag.lower() == "title":
            self.in_title = True
        if tag.lower() != "link":
            return
        rel = {part.lower() for part in clean(values.get("rel")).split()}
        media_type = clean(values.get("type")).lower().split(";", 1)[0]
        href = clean(values.get("href"))
        if "alternate" not in rel or media_type not in {"application/rss+xml", "application/atom+xml"} or not href:
            return
        url = urljoin(self.base_url, href)
        if not valid_web_url(url):
            return
        label = clean(values.get("title"))
        combined = f"{label} {url}".lower()
        score = 0
        if urlparse(url).netloc == urlparse(self.base_url).netloc:
            score += 4
        if media_type == "application/atom+xml":
            score += 1
        if any(word in combined for word in ("comment", "reply", "replies")):
            score -= 10
        self.candidates.append((score, url, label))

    def handle_endtag(self, tag):
        if tag.lower() == "title":
            self.in_title = False

    def handle_data(self, value):
        if self.in_title:
            self.title_parts.append(value)


def discover_feed(args):
    data = Path(args.document).read_bytes()
    text = data.decode("utf-8", "replace")
    head = text.lstrip("\ufeff \t\r\n")[:500].lower()
    is_feed = (
        "application/rss+xml" in args.content_type.lower()
        or "application/atom+xml" in args.content_type.lower()
        or re.match(r"(?:<\?xml[^>]*>\s*)?<(?:rss|feed|rdf:rdf)\b", head, re.IGNORECASE)
    )
    if is_feed and valid_web_url(args.page_url):
        print_json({"direct": True, "feed_url": args.page_url, "page_title": urlparse(args.page_url).netloc})
        return

    parser = DiscoveryParser(args.page_url)
    parser.feed(text)
    page_title = clean("".join(parser.title_parts)) or urlparse(args.page_url).netloc
    seen = set()
    candidates = []
    for score, url, label in sorted(parser.candidates, key=lambda item: -item[0]):
        if url in seen:
            continue
        seen.add(url)
        candidates.append({"score": score, "url": url, "label": label})
    if candidates:
        print_json({"direct": False, "feed_url": candidates[0]["url"], "page_title": page_title})


def local_name(tag):
    return tag.rsplit("}", 1)[-1].split(":", 1)[-1].lower()


def text_of(element):
    return clean("".join(element.itertext())) if element is not None else ""


class ForbiddenXMLDeclaration(Exception):
    pass


def parse_feed_xml(data):
    """Reject DTDs structurally before ElementTree can expand their entities."""
    parser = expat.ParserCreate()

    def reject_declaration(*_args):
        raise ForbiddenXMLDeclaration

    parser.StartDoctypeDeclHandler = reject_declaration
    parser.EntityDeclHandler = reject_declaration
    try:
        parser.Parse(data, True)
    except ForbiddenXMLDeclaration as error:
        raise NewsboatError("Advertised feed may not declare a DTD or entity", 4) from error
    except expat.ExpatError as error:
        raise NewsboatError(f"Advertised feed is not valid XML: {error}", 4) from error

    try:
        return ET.fromstring(data)
    except ET.ParseError as error:
        raise NewsboatError(f"Advertised feed is not valid XML: {error}", 4) from error


def validate_feed(args):
    data = Path(args.document).read_bytes()
    root = parse_feed_xml(data)

    root_name = local_name(root.tag)
    if root_name not in {"rss", "feed", "rdf"}:
        raise NewsboatError(f"Advertised document is not RSS or Atom: {args.feed_url}", 4)

    container = root
    if root_name in {"rss", "rdf"}:
        channel = next((item for item in root if local_name(item.tag) == "channel"), None)
        if channel is not None:
            container = channel

    title = ""
    for child in container:
        if local_name(child.tag) == "title":
            title = text_of(child)
            break
    title = title or clean(args.page_title) or urlparse(args.feed_url).netloc

    recent_titles = []
    for item in root.iter():
        if local_name(item.tag) not in {"item", "entry"}:
            continue
        item_title = next((text_of(child) for child in item if local_name(child.tag) == "title"), "")
        if item_title and item_title not in recent_titles:
            recent_titles.append(item_title)
        if len(recent_titles) == 3:
            break

    print_json(
        {
            "source_url": args.page_url,
            "feed_url": args.feed_url,
            "name": title,
            "recent_titles": recent_titles,
        }
    )


def unread_rows(cache_file, urls_file, columns, ordering):
    feeds = active_feed_urls(urls_file)
    if not feeds:
        return []
    placeholders = ",".join("?" for _ in feeds)
    database_uri = f"file:{quote(cache_file, safe='/')}?mode=ro"
    with sqlite3.connect(database_uri, uri=True) as database:
        database.row_factory = sqlite3.Row
        return list(
            database.execute(
                f"SELECT {columns} FROM rss_item WHERE unread = 1 AND deleted = 0 AND feedurl IN ({placeholders}) ORDER BY {ordering}",
                feeds,
            )
        )


def edition_signature(rows):
    signature = hashlib.sha256()
    for row in sorted(rows, key=lambda item: item["id"]):
        signature.update(f'{row["id"]}\0{row["guid"]}\0{row["feedurl"]}\0'.encode())
    return signature.hexdigest()


def create_brief_snapshot(args):
    rows = unread_rows(
        args.cache_file,
        args.urls_file,
        "id, guid, title, url, feedurl, pubDate, substr(content, 1, 12000) AS content",
        "pubDate DESC, id DESC",
    )
    if not rows:
        print_json({"total": 0, "articles": []})
        return

    groups = {}
    for row in rows:
        guid = row["guid"]
        if guid not in groups:
            groups[guid] = {
                "guid": guid,
                "title": row["title"],
                "url": row["url"],
                "feedurl": row["feedurl"],
                "published": row["pubDate"],
                "count": 0,
                "content": row["content"],
            }
        groups[guid]["count"] += 1

    articles = []
    markable_entries = 0
    excerpt_budget = EDITION_EXCERPT_LIMIT
    for group in list(groups.values())[:200]:
        group["id"] = f'A{len(articles) + 1:03d}'
        group["title"] = (group["title"] or "Untitled")[:300]
        group["excerpt"] = article_excerpt(group.pop("content"), min(EXCERPT_LIMIT, excerpt_budget))
        excerpt_budget -= len(group["excerpt"])
        group["content_status"] = "cached excerpt" if group["excerpt"] else "unavailable"
        group["markable"] = bool(group["excerpt"]) and bool(group["guid"]) and not any(character in group["guid"] for character in "\r\n")
        if group["markable"]:
            markable_entries += group["count"]
        articles.append(group)

    result = {
        "version": 1,
        "created_at": int(time.time()),
        "signature": edition_signature(rows),
        "total": len(rows),
        "markable_entries": markable_entries,
        "baseline_leave": len(rows) - markable_entries,
        "articles": articles,
    }
    with open(args.snapshot_file, "w", encoding="utf-8") as snapshot:
        json.dump(result, snapshot)
    print_json(result)


def prepare_triage(args):
    snapshot = read_json(args.snapshot_file)
    kept = json.loads(args.kept_json)
    require_fresh_snapshot(snapshot, "feed briefing")
    if len(kept) != len(set(kept)) or any(not re.fullmatch(r"A\d{3}", item) for item in kept):
        raise NewsboatError("The confirmation contains invalid or duplicate article IDs.")

    articles = snapshot.get("articles", [])
    by_id = {article.get("id"): article for article in articles}
    if len(by_id) != len(articles) or any(item not in by_id for item in kept):
        raise NewsboatError("The confirmation refers to an article outside this briefing.")

    kept_set = set(kept)
    to_mark = [article for article in articles if article.get("markable") and article["id"] not in kept_set]
    calculated_read = sum(article["count"] for article in to_mark)
    calculated_leave = snapshot["total"] - calculated_read
    if calculated_read != args.expected_read or calculated_leave != args.expected_leave:
        raise NewsboatError(
            f"Confirmation counts do not match this briefing: expected {calculated_read} read and {calculated_leave} left unread."
        )

    rows = unread_rows(args.cache_file, args.urls_file, "id, guid, feedurl", "id")
    if edition_signature(rows) != snapshot.get("signature") or len(rows) != snapshot.get("total"):
        raise NewsboatError("Your unread edition changed after the briefing. Run Brief Unread again before applying it.")

    target_guids = {article["guid"] for article in to_mark}
    affected = sum(1 for row in rows if row["guid"] in target_guids)
    if affected != calculated_read:
        raise NewsboatError("The briefing no longer maps cleanly to the unread edition. Run Brief Unread again.")

    with open(args.import_file, "w", encoding="utf-8", newline="\n") as destination:
        for guid in sorted(target_guids):
            destination.write(guid + "\n")
    print_json({"read": calculated_read, "leave": calculated_leave})


def validate_scout_apply(args):
    snapshot = read_json(args.snapshot_file)
    selected = json.loads(args.selected_json)
    require_fresh_snapshot(snapshot, "Feed Scout proposal")
    if len(selected) != args.expected_count or len(selected) != len(set(selected)):
        raise NewsboatError("The confirmed feed count does not match the selected Feed Scout IDs.")
    if any(not re.fullmatch(r"F\d{3}", item) for item in selected):
        raise NewsboatError("The confirmation contains an invalid feed ID.")

    candidates = snapshot.get("candidates", [])
    by_id = {candidate.get("id"): candidate for candidate in candidates}
    if len(by_id) != len(candidates) or any(item not in by_id for item in selected):
        raise NewsboatError("The confirmation refers to a feed outside this proposal.")

    current = active_feed_urls(args.urls_file)
    if current != snapshot.get("subscriptions"):
        raise NewsboatError("Subscriptions changed after this proposal. Run Feed Scout again before applying it.")

    feeds = []
    for item in selected:
        url = by_id[item].get("feed_url")
        if not isinstance(url, str) or not WEB_URL.fullmatch(url):
            raise NewsboatError("The proposal contains an invalid feed URL.")
        if url in current or url in feeds:
            raise NewsboatError("The proposal no longer maps to distinct new subscriptions.")
        feeds.append(url)
    print_json({"count": args.expected_count, "feeds": feeds, "target": os.path.realpath(args.urls_file)})


def build_parser():
    parser = argparse.ArgumentParser(description="Internal Newsboat data helper")
    commands = parser.add_subparsers(dest="command", required=True)

    command = commands.add_parser("subscriptions")
    command.add_argument("urls_file")
    command.set_defaults(handler=lambda args: print_json(read_subscriptions(args.urls_file)))

    command = commands.add_parser("discover")
    command.add_argument("page_url")
    command.add_argument("content_type")
    command.add_argument("document")
    command.set_defaults(handler=discover_feed)

    command = commands.add_parser("validate-feed")
    command.add_argument("page_url")
    command.add_argument("feed_url")
    command.add_argument("page_title")
    command.add_argument("document")
    command.set_defaults(handler=validate_feed)

    command = commands.add_parser("brief-snapshot")
    command.add_argument("cache_file")
    command.add_argument("urls_file")
    command.add_argument("snapshot_file")
    command.set_defaults(handler=create_brief_snapshot)

    command = commands.add_parser("triage-prepare")
    command.add_argument("snapshot_file")
    command.add_argument("cache_file")
    command.add_argument("urls_file")
    command.add_argument("expected_read", type=int)
    command.add_argument("expected_leave", type=int)
    command.add_argument("kept_json")
    command.add_argument("import_file")
    command.set_defaults(handler=prepare_triage)

    command = commands.add_parser("scout-apply")
    command.add_argument("snapshot_file")
    command.add_argument("urls_file")
    command.add_argument("expected_count", type=int)
    command.add_argument("selected_json")
    command.set_defaults(handler=validate_scout_apply)
    return parser


def main():
    args = build_parser().parse_args()
    try:
        args.handler(args)
    except NewsboatError as error:
        print(error, file=sys.stderr)
        raise SystemExit(error.exit_code) from error
    except (ET.ParseError, json.JSONDecodeError, KeyError, OSError, sqlite3.Error, TypeError, ValueError) as error:
        print(error, file=sys.stderr)
        raise SystemExit(1) from error


if __name__ == "__main__":
    main()
