import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { defineSecret } from "firebase-functions/params";
import { logger } from "firebase-functions/v2";

import { safeText } from "./sanitize";

const discordWebhookUrl = defineSecret("DISCORD_WEBHOOK_URL");

// Lookup tables are Maps, not object literals: `category` and `deviceModel`
// arrive from the client, and a plain-object lookup on a key like
// "constructor" or "__proto__" returns an inherited value instead of a miss.
const categoryColors = new Map<string, number>([
  ["bug", 0xe74c3c],
  ["feature", 0x3498db],
  ["praise", 0x2ecc71],
  ["other", 0x95a5a6],
]);

const DEFAULT_COLOR = 0x95a5a6;

const categoryEmoji = new Map<string, string>([
  ["bug", "🐛"],
  ["feature", "✨"],
  ["praise", "💚"],
  ["other", "💬"],
]);

// Maps Apple device identifiers to friendly model names.
// Identifier format: see https://gist.github.com/adamawolf/3048717
const friendlyDeviceNames = new Map<string, string>(Object.entries({
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
}));


export const notifyDiscordOnFeedback = onDocumentCreated(
  {
    document: "feedback/{docId}",
    secrets: [discordWebhookUrl],
    region: "us-central1",
    // /feedback accepts unauthenticated writes by design, so a flood is
    // possible. Cap the fan-out rather than letting it scale into unbounded
    // compute and an unbounded number of Discord posts.
    maxInstances: 3,
  },
  async (event) => {
    const data = event.data?.data();
    if (!data) {
      logger.warn("Feedback document had no data", { docId: event.params.docId });
      return;
    }

    // Everything below is client-supplied. The Firestore rules bound it, but
    // this function must not depend on that: it renders into a channel a human
    // reads, so it sanitises at the point of use.
    const rawCategory = String(data.category ?? "other");
    const category = categoryEmoji.has(rawCategory) ? rawCategory : "other";
    const message = safeText(String(data.message ?? "(no message)"), 3000);
    const replyEmail = data.replyEmail
      ? safeText(String(data.replyEmail), 254)
      : null;
    const uid = data.uid ? safeText(String(data.uid), 128) : null;
    const appVersion = safeText(String(data.appVersion ?? "?"), 64);
    const osVersion = safeText(String(data.osVersion ?? "?"), 64);
    const rawDeviceModel = String(data.deviceModel ?? "?");
    const deviceModel = safeText(rawDeviceModel, 64);
    const locale = safeText(String(data.locale ?? "?"), 64);

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
    // Only the lookup uses the raw identifier; the label is the escaped one.
    const friendlyName = friendlyDeviceNames.get(rawDeviceModel);
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
      // Nothing in a feedback report may ping anyone, whatever it contains.
      allowed_mentions: { parse: [] as string[] },
      embeds: [
        {
          title: `${categoryEmoji.get(category) ?? "💬"} ${category.toUpperCase()}`,
          description: message,
          color: categoryColors.get(category) ?? DEFAULT_COLOR,
          fields,
          // The document id is client-chosen too — `doc(id).set()` picks it —
          // so it gets the same treatment as everything else in the embed.
          footer: { text: `doc: ${safeText(event.params.docId, 64)}` },
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
