#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import sys


def replace_once(source_text: str, old: str, new: str, label: str, marker: str) -> str:
    if marker in source_text:
        return source_text
    if old not in source_text:
        raise RuntimeError(f"could not patch Hermes WhatsApp bridge ({label})")
    return source_text.replace(old, new, 1)


HELPER_BLOCK = """let connectionState = 'disconnected';

function logBridgeDiagnostic(event, payload = {}) {
  const entry = {
    event,
    timestamp: new Date().toISOString(),
    ...payload,
  };
  console.log(`[hermes-whatsapp-bridge] ${JSON.stringify(entry)}`);
}

function summarizeUpsertMessage(msg, batchType) {
  const key = msg?.key || {};
  const chatId = key.remoteJid || '';
  const senderId = key.participant || chatId;
  return {
    batchType,
    messageId: key.id || '',
    remoteJid: chatId,
    senderId,
    fromMe: Boolean(key.fromMe),
    hasMessage: Boolean(msg?.message),
    messageStubType: msg?.messageStubType ?? null,
    messageTypes: msg?.message ? Object.keys(msg.message) : [],
  };
}
"""


def patch_bridge(source_text: str) -> str:
    source_text = replace_once(
        source_text,
        "let connectionState = 'disconnected';\n",
        HELPER_BLOCK,
        "helpers",
        "function logBridgeDiagnostic(event, payload = {}) {",
    )
    source_text = replace_once(
        source_text,
        "    if (type !== 'notify') return;\n",
        """    if (type !== 'notify') {
      logBridgeDiagnostic('messages.upsert.skipped', {
        reason: 'non-notify-batch',
        batchType: type,
        count: Array.isArray(messages) ? messages.length : 0,
      });
      return;
    }
""",
        "notify guard",
        "reason: 'non-notify-batch'",
    )
    source_text = replace_once(
        source_text,
        "    for (const msg of messages) {\n",
        """    for (const msg of messages) {
      const summary = summarizeUpsertMessage(msg, type);
""",
        "upsert summary",
        "const summary = summarizeUpsertMessage(msg, type);",
    )
    source_text = replace_once(
        source_text,
        "      if (!msg.message) continue;\n",
        """      if (!msg.message) {
        logBridgeDiagnostic('messages.upsert.skipped', {
          ...summary,
          reason: 'missing-message-payload',
        });
        continue;
      }
""",
        "missing message payload",
        "reason: 'missing-message-payload'",
    )
    source_text = replace_once(
        source_text,
        "        if (isGroup || chatId.includes('status')) continue;\n",
        """        if (isGroup || chatId.includes('status')) {
          logBridgeDiagnostic('messages.upsert.skipped', {
            ...summary,
            reason: 'fromMe-group-or-status',
            chatId,
          });
          continue;
        }
""",
        "group or status self-message",
        "reason: 'fromMe-group-or-status'",
    )
    source_text = replace_once(
        source_text,
        """          // Bot mode: separate number. ALL fromMe are echo-backs of our own replies — skip.
          continue;
""",
        """          // Bot mode: separate number. ALL fromMe are echo-backs of our own replies — skip.
          logBridgeDiagnostic('messages.upsert.skipped', {
            ...summary,
            reason: 'fromMe-bot-echo',
            chatId,
          });
          continue;
""",
        "bot echo skip",
        "reason: 'fromMe-bot-echo'",
    )
    source_text = replace_once(
        source_text,
        "        if (!isSelfChat) continue;\n",
        """        if (!isSelfChat) {
          logBridgeDiagnostic('messages.upsert.skipped', {
            ...summary,
            reason: 'fromMe-not-self-chat',
            chatId,
            myNumber,
            chatNumber,
          });
          continue;
        }
""",
        "not self-chat skip",
        "reason: 'fromMe-not-self-chat'",
    )
    source_text = replace_once(
        source_text,
        """      if (!msg.key.fromMe && ALLOWED_USERS.length > 0 && !ALLOWED_USERS.includes(senderNumber)) {
        continue;
      }
""",
        """      if (!msg.key.fromMe && ALLOWED_USERS.length > 0 && !ALLOWED_USERS.includes(senderNumber)) {
        logBridgeDiagnostic('messages.upsert.skipped', {
          ...summary,
          reason: 'unauthorized-sender',
          senderNumber,
          allowedUsers: ALLOWED_USERS,
        });
        continue;
      }
""",
        "allowlist skip",
        "reason: 'unauthorized-sender'",
    )
    source_text = replace_once(
        source_text,
        "      if (!body && !hasMedia) continue;\n",
        """      if (!body && !hasMedia) {
        logBridgeDiagnostic('messages.upsert.skipped', {
          ...summary,
          reason: 'empty-body-no-media',
          chatId,
          senderNumber,
        });
        continue;
      }
""",
        "empty body skip",
        "reason: 'empty-body-no-media'",
    )
    source_text = replace_once(
        source_text,
        "      messageQueue.push(event);\n",
        """      logBridgeDiagnostic('messages.upsert.accepted', {
        ...summary,
        chatId,
        senderNumber,
        isGroup,
        hasMedia,
        mediaType,
        bodyPreview: body.slice(0, 160),
        queueLengthBefore: messageQueue.length,
      });

      messageQueue.push(event);
""",
        "accepted event log",
        "messages.upsert.accepted",
    )
    source_text = replace_once(
        source_text,
        """      if (messageQueue.length > MAX_QUEUE_SIZE) {
        messageQueue.shift();
      }
""",
        """      if (messageQueue.length > MAX_QUEUE_SIZE) {
        messageQueue.shift();
      }

      logBridgeDiagnostic('messages.upsert.queued', {
        messageId: event.messageId,
        chatId: event.chatId,
        queueLength: messageQueue.length,
      });
""",
        "queued event log",
        "messages.upsert.queued",
    )
    source_text = replace_once(
        source_text,
        """app.get('/messages', (req, res) => {
  const msgs = messageQueue.splice(0, messageQueue.length);
  res.json(msgs);
});
""",
        """app.get('/messages', (req, res) => {
  const msgs = messageQueue.splice(0, messageQueue.length);
  if (msgs.length > 0) {
    logBridgeDiagnostic('messages.poll.drained', {
      count: msgs.length,
      messageIds: msgs.map((msg) => msg.messageId),
      queueLengthAfterDrain: messageQueue.length,
    });
  }
  res.json(msgs);
});
""",
        "/messages endpoint",
        "messages.poll.drained",
    )
    return source_text


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print("Usage: patch-whatsapp-bridge.py /path/to/bridge.js", file=sys.stderr)
        return 1

    target = Path(argv[1])
    source_text = target.read_text(encoding="utf-8")
    patched = patch_bridge(source_text)
    if patched != source_text:
        target.write_text(patched, encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
