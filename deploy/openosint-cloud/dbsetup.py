#!/usr/bin/env python3
"""
One-shot database setup, run on the Heroku dyno:

    heroku run python dbsetup.py -a <app>

Loads the schema and mints an API key, printing the key once. Running it again
is safe: the schema uses CREATE TABLE IF NOT EXISTS, and --mint adds a new key
rather than replacing existing ones.

Runs on the dyno rather than locally so no psql client is needed, and
DATABASE_URL is already in the environment there.
"""
from __future__ import annotations

import argparse
import asyncio
import os
import pathlib
import secrets
import sys

import asyncpg

SCHEMA = pathlib.Path(__file__).parent / "db" / "init.sql"


async def connect() -> asyncpg.Connection:
    url = os.environ.get("DATABASE_URL", "")
    if not url:
        sys.exit("DATABASE_URL is not set. Is the Postgres addon attached?")
    # Heroku exposes a postgres:// DSN; asyncpg requires postgresql://.
    dsn = url.replace("postgres://", "postgresql://", 1)
    try:
        return await asyncpg.connect(dsn)
    except Exception:
        # Heroku Postgres requires TLS; retry explicitly if the plain attempt
        # was rejected rather than failing with a bare handshake error.
        return await asyncpg.connect(dsn, ssl="require")


async def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--schema", action="store_true", help="load db/init.sql")
    ap.add_argument("--mint", action="store_true", help="create an API key")
    ap.add_argument("--credits", type=int, default=100_000)
    ap.add_argument("--plan", default="pro")
    args = ap.parse_args()
    # No flags means do both — the common first-run case.
    if not args.schema and not args.mint:
        args.schema = args.mint = True

    conn = await connect()
    try:
        if args.schema:
            if not SCHEMA.exists():
                sys.exit(f"Schema not found at {SCHEMA}")
            await conn.execute(SCHEMA.read_text())
            print("Schema loaded.")

        if args.mint:
            key = secrets.token_urlsafe(32)
            await conn.execute(
                "INSERT INTO customers (api_key, credits, plan) VALUES ($1, $2, $3)",
                key,
                args.credits,
                args.plan,
            )
            print("")
            print("API key (shown once — save it now):")
            print(f"  {key}")
            print("")
            print(f"credits={args.credits} plan={args.plan}")
    finally:
        await conn.close()


if __name__ == "__main__":
    asyncio.run(main())
