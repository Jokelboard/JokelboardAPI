#!/usr/bin/env python3
"""
python-client.py

Board API example using Python 3 + the `requests` library.

Install:
    pip install requests

Usage:
    export JKB_TOKEN="jkb_..."
    export BOARD_ID="your-board-id"
    python python-client.py

Demonstrates:
  - Token introspection
  - Listing boards
  - Creating a list + multiple cards from a CSV-like dataset
  - Using PATCH to update custom fieldValues (descriptionMode: "fields")
  - Proper 409 revision handling with exponential backoff
"""

import os
import sys
import time
import json
import requests
from datetime import datetime, timezone

BASE = "https://jokelboard.com/api/v1"
TOKEN = os.environ.get("JKB_TOKEN")
BOARD_ID = os.environ.get("BOARD_ID")

if not TOKEN or not BOARD_ID:
    print("Usage: JKB_TOKEN=jkb_... BOARD_ID=board-... python python-client.py", file=sys.stderr)
    sys.exit(1)

SESSION = requests.Session()
SESSION.headers.update({
    "Authorization": f"Bearer {TOKEN}",
    "Content-Type": "application/json",
    "User-Agent": "JokelboardAPI-Python-Example/1.0",
})

def api(method, path, **kwargs):
    url = f"{BASE}{path}"
    resp = SESSION.request(method, url, timeout=30, **kwargs)
    try:
        body = resp.json()
    except Exception:
        body = {"raw": resp.text}
    if not resp.ok:
        err = RuntimeError(body.get("message") or body.get("error") or f"HTTP {resp.status}")
        err.status = resp.status_code
        err.body = body
        raise err
    return body

def get_board():
    return api("GET", f"/boards/{BOARD_ID}")["board"]

def create_list(title):
    return api("POST", f"/boards/{BOARD_ID}/lists", json={"title": title})["list"]

def create_card(list_id, payload, revision):
    payload = {**payload, "revision": revision}
    return api("POST", f"/boards/{BOARD_ID}/cards", json=payload)["card"]

def patch_card(card_id, patch, revision):
    patch = {**patch, "revision": revision}
    return api("PATCH", f"/boards/{BOARD_ID}/cards/{card_id}", json=patch)["card"]

def add_comment(card_id, text, revision):
    return api("POST", f"/boards/{BOARD_ID}/cards/{card_id}/comments",
               json={"text": text, "revision": revision})

def move_card(card_id, to_list_id, position, revision):
    return api("POST", f"/boards/{BOARD_ID}/cards/{card_id}/move",
               json={"toListId": to_list_id, "position": position, "revision": revision})

def main():
    print("=== Jokelboard Board API — Python Example ===\n")

    # 1. Who am I?
    me = api("GET", "/me")
    print(f"Authenticated as {me['user']['username']} (tier: {me['user']['tier']})")
    print(f"Token: {me['token']['name']} — scopes: {', '.join(me['token']['scopes'])}\n")

    # 2. Current board state
    board = get_board()
    print(f"Board: {board['name']}")
    print(f"Revision: {board['revision']}")
    print(f"Existing lists: {len(board['data'].get('lists', []))}\n")

    # 3. Find or create "Python Imports" list
    lists = board["data"].get("lists", [])
    target_list = next((l for l in lists if l["title"] == "Python Imports"), None)
    if not target_list:
        target_list = create_list("Python Imports")
        print(f"Created list: {target_list['title']}")
    else:
        print(f"Using existing list: {target_list['title']}")

    # 4. Import a batch of items (imagine this comes from a CSV, Jira export, RSS feed, etc.)
    work_items = [
        {"title": "Migrate legacy auth service to new OIDC provider", "severity": "P1", "labels": ["auth", "migration"]},
        {"title": "Add SLO dashboard for checkout flow", "severity": "P2", "labels": ["observability"]},
        {"title": "Document fieldValues usage in the public API", "severity": "P3", "labels": ["docs", "api"]},
    ]

    current_rev = board["revision"]
    created_cards = []

    for item in work_items:
        card_payload = {
            "listId": target_list["id"],
            "title": item["title"],
            "severity": item["severity"],
            "description": f"Imported at {datetime.now(timezone.utc).isoformat()}",
            "descriptionMode": "markdown",
            "labels": [{"name": lbl, "color": "#c7ff5e"} for lbl in item.get("labels", [])],
            "fieldValues": {
                "source": "python-example",
                "import-batch": "2026-05-demo",
            },
        }
        try:
            card = create_card(target_list["id"], card_payload, current_rev)
        except RuntimeError as e:
            if getattr(e, "status", None) == 409:
                print("  [!] 409 revision conflict — refetching...")
                board = get_board()
                current_rev = board["revision"]
                card = create_card(target_list["id"], card_payload, current_rev)
            else:
                raise
        print(f"  + {card['title']}  (id={card['id']}, ticket={card.get('ticket')})")
        created_cards.append(card)
        current_rev = card.get("revision") or current_rev   # server returns updated board in some paths
        time.sleep(0.2)  # be nice to the burst limiter

    # 5. Update the middle card with custom fields + descriptionMode=fields
    if len(created_cards) >= 2:
        middle = created_cards[1]
        print(f"\nUpdating card {middle['id']} with fieldValues + descriptionMode=fields...")
        updated = patch_card(
            middle["id"],
            {
                "descriptionMode": "fields",
                "fieldValues": {
                    "source": "python-example",
                    "import-batch": "2026-05-demo",
                    "owner-team": "platform",
                    "estimated-hours": 6,
                    "ready-for-review": True,
                },
                "description": "This card now uses structured fields instead of markdown.",
            },
            current_rev,
        )
        print(f"  ✓ descriptionMode now '{updated.get('descriptionMode')}'")
        print(f"  ✓ fieldValues keys: {list(updated.get('fieldValues', {}).keys())}")
        current_rev = updated.get("revision") or current_rev

    # 6. Move the last card to a "Done" list (create one if needed)
    done_list = next((l for l in board["data"].get("lists", []) if "done" in l["title"].lower()), None)
    if not done_list:
        done_list = create_list("Done (from Python)")
        print(f"\nCreated Done list: {done_list['title']}")

    last_card = created_cards[-1]
    print(f"\nMoving {last_card['id']} to top of '{done_list['title']}'...")
    move_card(last_card["id"], done_list["id"], 0, current_rev)
    print("  ✓ Card moved successfully")

    print("\n✅ Python example finished. Check the board in the Jokelboard UI.")
    print("   On organisation boards you will also see these actions in the audit log.")

if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"\n❌ {exc}", file=sys.stderr)
        if hasattr(exc, "body"):
            print(json.dumps(exc.body, indent=2), file=sys.stderr)
        sys.exit(1)
