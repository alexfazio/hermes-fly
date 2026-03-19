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
const recentMessageIds = new Set();
const recentMessageIdOrder = [];
const MAX_RECENT_MESSAGE_IDS = 512;
const APPEND_RECENT_WINDOW_MS = 2 * 60 * 1000;

function getSelfJid() {
  return (sock?.user?.id || '').replace(/:.*@/, '@');
}

function getSelfNumber() {
  return getSelfJid().replace(/@.*/, '');
}

function unwrapMessageContent(message) {
  let current = message;
  while (current && typeof current === 'object') {
    if (current.deviceSentMessage?.message) {
      current = current.deviceSentMessage.message;
      continue;
    }
    if (current.ephemeralMessage?.message) {
      current = current.ephemeralMessage.message;
      continue;
    }
    if (current.viewOnceMessage?.message) {
      current = current.viewOnceMessage.message;
      continue;
    }
    if (current.viewOnceMessageV2?.message) {
      current = current.viewOnceMessageV2.message;
      continue;
    }
    if (current.viewOnceMessageV2Extension?.message) {
      current = current.viewOnceMessageV2Extension.message;
      continue;
    }
    if (current.documentWithCaptionMessage?.message) {
      current = current.documentWithCaptionMessage.message;
      continue;
    }
    if (current.editedMessage?.message) {
      current = current.editedMessage.message;
      continue;
    }
    if (current.protocolMessage?.editedMessage) {
      current = current.protocolMessage.editedMessage;
      continue;
    }
    break;
  }
  return current;
}

function getMessageTimestampMs(msg) {
  const raw = msg?.messageTimestamp;
  if (typeof raw === 'number') return raw * 1000;
  if (typeof raw === 'bigint') return Number(raw) * 1000;
  if (typeof raw === 'string' && /^[0-9]+$/.test(raw)) return Number(raw) * 1000;
  if (raw && typeof raw.toNumber === 'function') return raw.toNumber() * 1000;
  return 0;
}

function rememberMessageId(messageId) {
  if (!messageId) {
    return true;
  }
  if (recentMessageIds.has(messageId)) {
    return false;
  }
  recentMessageIds.add(messageId);
  recentMessageIdOrder.push(messageId);
  if (recentMessageIdOrder.length > MAX_RECENT_MESSAGE_IDS) {
    const evicted = recentMessageIdOrder.shift();
    if (evicted) recentMessageIds.delete(evicted);
  }
  return true;
}

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
  const content = unwrapMessageContent(msg?.message);
  return {
    batchType,
    messageId: key.id || '',
    remoteJid: chatId,
    senderId,
    fromMe: Boolean(key.fromMe),
    hasMessage: Boolean(msg?.message),
    messageStubType: msg?.messageStubType ?? null,
    protocolType: msg?.message?.protocolMessage?.type ?? null,
    messageTypes: content ? Object.keys(content) : [],
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
        """    } else if (connection === 'open') {
      connectionState = 'connected';
      console.log('✅ WhatsApp connected!');
      if (PAIR_ONLY) {
""",
        """    } else if (connection === 'open') {
      connectionState = 'connected';
      console.log('✅ WhatsApp connected!');
      logBridgeDiagnostic('connection.open', {
        selfJid: getSelfJid(),
        selfNumber: getSelfNumber(),
      });
      if (PAIR_ONLY) {
""",
        "connection open identity",
        "logBridgeDiagnostic('connection.open'",
    )
    source_text = replace_once(
        source_text,
        """app.get('/health', (req, res) => {
  res.json({
    status: connectionState,
    queueLength: messageQueue.length,
    uptime: process.uptime(),
  });
});
""",
        """app.get('/health', (req, res) => {
  res.json({
    status: connectionState,
    queueLength: messageQueue.length,
    uptime: process.uptime(),
    // hermes-fly: expose paired account identity for self-chat validation
    selfJid: getSelfJid(),
    selfNumber: getSelfNumber(),
  });
});
""",
        "health identity",
        "hermes-fly: expose paired account identity for self-chat validation",
    )
    source_text = replace_once(
        source_text,
        "    if (type !== 'notify') return;\n",
        """    const allowAppendBatch = WHATSAPP_MODE === 'self-chat' && type === 'append';
    if (type !== 'notify' && !allowAppendBatch) {
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
        "      const chatId = msg.key.remoteJid;\n",
        """      const content = unwrapMessageContent(msg.message);
      const timestampMs = getMessageTimestampMs(msg);
      if (type === 'append' && timestampMs > 0) {
        const ageMs = Date.now() - timestampMs;
        if (ageMs > APPEND_RECENT_WINDOW_MS) {
          logBridgeDiagnostic('messages.upsert.skipped', {
            ...summary,
            reason: 'append-too-old',
            ageMs,
          });
          continue;
        }
      }

      const chatId = msg.key.remoteJid;
""",
        "content unwrap and append gate",
        "reason: 'append-too-old'",
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
        """      if (msg.message.conversation) {
        body = msg.message.conversation;
      } else if (msg.message.extendedTextMessage?.text) {
        body = msg.message.extendedTextMessage.text;
      } else if (msg.message.imageMessage) {
        body = msg.message.imageMessage.caption || '';
        hasMedia = true;
        mediaType = 'image';
      } else if (msg.message.videoMessage) {
        body = msg.message.videoMessage.caption || '';
        hasMedia = true;
        mediaType = 'video';
      } else if (msg.message.audioMessage || msg.message.pttMessage) {
        hasMedia = true;
        mediaType = msg.message.pttMessage ? 'ptt' : 'audio';
      } else if (msg.message.documentMessage) {
        body = msg.message.documentMessage.caption || msg.message.documentMessage.fileName || '';
        hasMedia = true;
        mediaType = 'document';
      }
""",
        """      if (content?.conversation) {
        body = content.conversation;
      } else if (content?.extendedTextMessage?.text) {
        body = content.extendedTextMessage.text;
      } else if (content?.imageMessage) {
        body = content.imageMessage.caption || '';
        hasMedia = true;
        mediaType = 'image';
      } else if (content?.videoMessage) {
        body = content.videoMessage.caption || '';
        hasMedia = true;
        mediaType = 'video';
      } else if (content?.audioMessage || content?.pttMessage) {
        hasMedia = true;
        mediaType = content.pttMessage ? 'ptt' : 'audio';
      } else if (content?.documentMessage) {
        body = content.documentMessage.caption || content.documentMessage.fileName || '';
        hasMedia = true;
        mediaType = 'document';
      }
""",
        "unwrapped content extraction",
        "content?.conversation",
    )
    source_text = replace_once(
        source_text,
        "      if (!body && !hasMedia) continue;\n",
        """      if (!body && !hasMedia) {
        logBridgeDiagnostic('messages.upsert.skipped', {
          ...summary,
          reason: summary.protocolType !== null ? 'protocol-message-no-content' : 'empty-body-no-media',
          chatId,
          senderNumber,
        });
        continue;
      }
""",
        "empty body skip",
        "protocol-message-no-content",
    )
    source_text = replace_once(
        source_text,
        "      const event = {\n",
        """      if (!rememberMessageId(msg.key.id)) {
        logBridgeDiagnostic('messages.upsert.skipped', {
          ...summary,
          reason: 'duplicate-message-id',
        });
        continue;
      }

      const event = {
""",
        "duplicate message guard",
        "reason: 'duplicate-message-id'",
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
