#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import sys


def replace_once(source_text: str, old: str, new: str, label: str, marker: str) -> str:
    if marker in source_text:
        return source_text
    if old not in source_text:
        raise RuntimeError(f"could not patch Hermes gateway ({label})")
    return source_text.replace(old, new, 1)


def patch_base(source_text: str) -> str:
    source_text = replace_once(
        source_text,
        "    async def send_typing(self, chat_id: str) -> None:\n",
        "    async def send_typing(self, chat_id: str, metadata=None) -> None:\n",
        "base send_typing signature",
        "async def send_typing(self, chat_id: str, metadata=None) -> None:",
    )
    source_text = replace_once(
        source_text,
        "    async def _keep_typing(self, chat_id: str, interval: float = 2.0) -> None:\n",
        "    async def _keep_typing(self, chat_id: str, interval: float = 2.0, metadata=None) -> None:\n",
        "base _keep_typing signature",
        "async def _keep_typing(self, chat_id: str, interval: float = 2.0, metadata=None) -> None:",
    )
    source_text = replace_once(
        source_text,
        "                await self.send_typing(chat_id)\n",
        "                await self.send_typing(chat_id, metadata=metadata)\n",
        "base _keep_typing metadata forwarding",
        "await self.send_typing(chat_id, metadata=metadata)",
    )
    return source_text


def patch_signal(source_text: str) -> str:
    source_text = replace_once(
        source_text,
        "    async def send_typing(self, chat_id: str) -> None:\n",
        "    async def send_typing(self, chat_id: str, metadata=None) -> None:\n",
        "signal send_typing signature",
        "async def send_typing(self, chat_id: str, metadata=None) -> None:",
    )
    return source_text


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print("Usage: patch-hermes-gateway.py /path/to/hermes-agent", file=sys.stderr)
        return 1

    root = Path(argv[1]).expanduser().resolve()
    base_path = root / "gateway" / "platforms" / "base.py"
    signal_path = root / "gateway" / "platforms" / "signal.py"

    base_path.write_text(patch_base(base_path.read_text(encoding="utf-8")), encoding="utf-8")
    signal_path.write_text(patch_signal(signal_path.read_text(encoding="utf-8")), encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
