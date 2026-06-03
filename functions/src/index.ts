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
    fields.push({
      name: "Device",
      value: `${deviceModel} · ${osVersion}`,
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
