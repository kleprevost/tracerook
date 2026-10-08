"""Operator CLI. API keys are shown once at creation and only their keyed hash is stored.

  tracerook-admin create-account alice@example.com      # prints a new API key
  tracerook-admin new-key alice@example.com             # additional key
  tracerook-admin revoke-keys alice@example.com
  tracerook-admin set-state alice@example.com canceled  # active|past_due|canceled|suspended
  tracerook-admin list
Billing webhooks (e.g. Stripe) should call the same Store methods to set the account state."""
from __future__ import annotations

import argparse
import sys

from .config import ConfigError, Settings
from .security import display_prefix, generate_api_key, hash_api_key
from .store import ACCOUNT_STATES, Store


def _issue_key(store: Store, settings: Settings, account_id: str) -> str:
    key = generate_api_key()
    store.add_api_key(account_id, hash_api_key(settings.key_pepper, key), display_prefix(key))
    return key


def run(argv: list[str], settings: Settings, store: Store, out=sys.stdout) -> int:
    p = argparse.ArgumentParser(prog="tracerook-admin")
    sub = p.add_subparsers(dest="cmd", required=True)
    c = sub.add_parser("create-account"); c.add_argument("email"); c.add_argument("--plan", default="individual")
    k = sub.add_parser("new-key"); k.add_argument("email")
    r = sub.add_parser("revoke-keys"); r.add_argument("email")
    s = sub.add_parser("set-state"); s.add_argument("email"); s.add_argument("state", choices=ACCOUNT_STATES)
    sub.add_parser("list")
    args = p.parse_args(argv)

    if args.cmd == "list":
        for a in store.list_accounts():
            live = sum(1 for key in store.list_api_keys(a["id"]) if not key["revoked_at"])
            print(f'{a["id"]}  {a["email"]}  {a["plan"]}  {a["state"]}  keys={live}', file=out)
        return 0
    if args.cmd == "create-account":
        from .plans import build_plans
        if args.plan not in build_plans(settings):
            print(f"unknown plan: {args.plan}", file=sys.stderr)
            return 2
        account = store.create_account(args.email, args.plan)
        print(f'account: {account["id"]}\nAPI key (shown once): {_issue_key(store, settings, account["id"])}', file=out)
        return 0
    account = store.get_account_by_email(args.email)
    if account is None:
        print("no such account", file=sys.stderr)
        return 1
    if args.cmd == "new-key":
        print(f'API key (shown once): {_issue_key(store, settings, account["id"])}', file=out)
    elif args.cmd == "revoke-keys":
        print(f'revoked {store.revoke_api_keys(account["id"])} key(s)', file=out)
    elif args.cmd == "set-state":
        store.update_account(account["id"], state=args.state)
        print(f'{account["email"]} -> {args.state}', file=out)
    return 0


def main() -> None:
    try:
        settings = Settings.from_env(require_analyzer=False)
    except ConfigError as exc:
        sys.exit(f"config error: {exc}")
    store = Store(settings.database_path)
    sys.exit(run(sys.argv[1:], settings, store))


if __name__ == "__main__":
    main()
