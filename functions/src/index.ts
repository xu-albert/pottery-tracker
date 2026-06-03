import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { defineSecret } from "firebase-functions/params";
import { logger } from "firebase-functions/v2";

const discordWebhookUrl = defineSecret("DISCORD_WEBHOOK_URL");

const categoryColors: Record<string, number> = {
  bug: 0xe74c3c,
  feature: 0x3498db,
  praise: 0x2ecc71,
  other: 0x95a5a6,
};

const categoryEmoji: Record<string, string> = {
  bug: "🐛",
  feature: "✨",
  praise: "💚",
  other: "💬",
};

// Maps Apple device identifiers to friendly model names.
// Identifier format: see https://gist.github.com/adamawolf/3048717
const friendlyDeviceNames: Record<string, string> = {
  // iPhone 16 family
  "iPhone17,1": "iPhone 16 Pro",
  "iPhone17,2": "iPhone 16 Pro Max",
  "iPhone17,3": "iPhone 16",
  "iPhone17,4": "iPhone 16 Plus",
  "iPhone17,5": "iPhone 16e",
  // iPhone 15 family
  "iPhone15,4": "iPhone 15",
  "iPhone15,5": "iPhone 15 Plus",
  "iPhone16,1": "iPhone 15 Pro",
  "iPhone16,2": "iPhone 15 Pro Max",
  // iPhone 14 family
  "iPhone14,7": "iPhone 14",
  "iPhone14,8": "iPhone 14 Plus",
  "iPhone15,2": "iPhone 14 Pro",
  "iPhone15,3": "iPhone 14 Pro Max",
  // iPhone 13 family
  "iPhone14,5": "iPhone 13",
  "iPhone14,4": "iPhone 13 mini",
  "iPhone14,2": "iPhone 13 Pro",
  "iPhone14,3": "iPhone 13 Pro Max",
  // iPhone 12 family
  "iPhone13,2": "iPhone 12",
  "iPhone13,1": "iPhone 12 mini",
  "iPhone13,3": "iPhone 12 Pro",
  "iPhone13,4": "iPhone 12 Pro Max",
  // iPhone 11 family
  "iPhone12,1": "iPhone 11",
  "iPhone12,3": "iPhone 11 Pro",
  "iPhone12,5": "iPhone 11 Pro Max",
  // iPhone SE
  "iPhone14,6": "iPhone SE (3rd gen)",
  "iPhone12,8": "iPhone SE (2nd gen)",
  // iPad Pro (M4)
  "iPad16,3": "iPad Pro 11\" M4",
  "iPad16,4": "iPad Pro 11\" M4 (cellular)",
  "iPad16,5": "iPad Pro 13\" M4",
  "iPad16,6": "iPad Pro 13\" M4 (cellular)",
  // iPad Air (M2)
  "iPad14,8": "iPad Air 11\" M2",
  "iPad14,9": "iPad Air 11\" M2 (cellular)",
  "iPad14,10": "iPad Air 13\" M2",
  "iPad14,11": "iPad Air 13\" M2 (cellular)",
};

export const notifyDiscordOnFeedback = onDocumentCreated(
  {
    document: "feedback/{docId}",
    secrets: [discordWebhookUrl],
    region: "us-central1",
  },
  async (event) => {
    const data = event.data?.data();
    if (!data) {
      logger.warn("Feedback document had no data", { docId: event.params.docId });
      return;
    }

    const category = String(data.category ?? "other");
    const message = String(data.message ?? "(no message)");
    const replyEmail = data.replyEmail ? String(data.replyEmail) : null;
    const uid = data.uid ? String(data.uid) : null;
    const appVersion = String(data.appVersion ?? "?");
    const osVersion = String(data.osVersion ?? "?");
    const deviceModel = String(data.deviceModel ?? "?");
    const locale = String(data.locale ?? "?");

    const fields: Array<{ name: string; value: string; inline?: boolean }> = [];

    if (replyEmail) {
      fields.push({ name: "Reply email", value: replyEmail, inline: true });
    } else {
      fields.push({ name: "Reply email", value: "_(none provided)_", inline: true });
    }
    fields.push({
      name: "User",
      value: uid ? `\`${uid}\`` : "_anonymous_",
      inline: true,
    });
    fields.push({
      name: "App",
      value: `v${appVersion} · ${locale}`,
      inline: true,
    });
    const friendlyName = friendlyDeviceNames[deviceModel];
    const deviceLabel = friendlyName
      ? `${deviceModel} (${friendlyName})`
      : deviceModel;
    fields.push({
      name: "Device",
      value: `${deviceLabel} · ${osVersion}`,
      inline: true,
    });

    const payload = {
      username: "Potter Journal Feedback",
      embeds: [
        {
          title: `${categoryEmoji[category] ?? "💬"} ${category.toUpperCase()}`,
          description: message.length > 4000 ? message.slice(0, 4000) + "…" : message,
          color: categoryColors[category] ?? categoryColors.other,
          fields,
          footer: { text: `doc: ${event.params.docId}` },
          timestamp: new Date().toISOString(),
        },
      ],
    };

    try {
      const response = await fetch(discordWebhookUrl.value(), {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload),
      });
      if (!response.ok) {
        const body = await response.text();
        logger.error("Discord webhook returned non-2xx", {
          status: response.status,
          body,
          docId: event.params.docId,
        });
      }
    } catch (err) {
      logger.error("Discord webhook POST failed", { err, docId: event.params.docId });
    }
  }
);
