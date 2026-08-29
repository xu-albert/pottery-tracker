// Runs the deployed handler itself (not just the sanitiser) against feedback
// documents an attacker could write, and inspects the request it would send
// to Discord. `fetch` is stubbed, so nothing leaves the process.
const test = require("node:test");
const assert = require("node:assert/strict");

process.env.DISCORD_WEBHOOK_URL = "https://discord.test/api/webhooks/1/abc";
const { notifyDiscordOnFeedback } = require("../lib/index");

/** Runs the handler for one feedback doc and returns every POST it made. */
async function runWith(data, { docId = "doc-1", respond } = {}) {
  const calls = [];
  const realFetch = globalThis.fetch;
  globalThis.fetch = async (url, init) => {
    calls.push({ url, init });
    if (respond) return respond();
    return { ok: true, status: 204, text: async () => "" };
  };
  try {
    await notifyDiscordOnFeedback.run({
      data: data === undefined ? undefined : { data: () => data },
      params: { docId },
    });
  } finally {
    globalThis.fetch = realFetch;
  }
  return calls;
}

async function postedPayload(data, opts) {
  const calls = await runWith(data, opts);
  assert.equal(calls.length, 1, "exactly one webhook POST");
  assert.equal(calls[0].url, process.env.DISCORD_WEBHOOK_URL);
  assert.equal(calls[0].init.method, "POST");
  return JSON.parse(calls[0].init.body);
}

const field = (payload, name) =>
  payload.embeds[0].fields.find((f) => f.name === name).value;

test("a report cannot ping anyone, whatever it says", async () => {
  const payload = await postedPayload({
    category: "bug",
    message: "@everyone @here <@123456> <@&789> please look",
    replyEmail: "@everyone",
    uid: "<@123456>",
  });
  // Discord honours mentions only when the request allows them; an empty
  // parse list with no users/roles allow-list suppresses every kind.
  assert.deepEqual(payload.allowed_mentions, { parse: [] });
  assert.deepEqual(Object.keys(payload.allowed_mentions), ["parse"]);
});

test("markdown in every client field is escaped, not rendered", async () => {
  const payload = await postedPayload({
    category: "feature",
    message: "[click](https://evil.test) **urgent**",
    replyEmail: "_under_score_@x.test",
    uid: "abc`**owned**",
    appVersion: "1.0 ~~old~~",
    locale: "en||spoiler||",
    osVersion: "> 17",
    deviceModel: "# Big",
  });
  const embed = payload.embeds[0];
  assert.equal(embed.description, "\\[click\\]\\(https://evil.test\\) \\*\\*urgent\\*\\*");
  assert.equal(field(payload, "Reply email"), "\\_under\\_score\\_@x.test");
  // The uid sits in a code span; the backtick must not close it early.
  assert.equal(field(payload, "User"), "`abc\\`\\*\\*owned\\*\\*`");
  assert.equal(field(payload, "App"), "v1.0 \\~\\~old\\~\\~ · en\\|\\|spoiler\\|\\|");
  assert.equal(field(payload, "Device"), "\\# Big · \\> 17");
});

test("the client-chosen document id is escaped in the footer", async () => {
  const payload = await postedPayload(
    { category: "other", message: "hi" },
    { docId: "x](https://evil.test)" },
  );
  assert.equal(payload.embeds[0].footer.text, "doc: x\\]\\(https://evil.test\\)");
});

test("a hostile category or device id cannot reach inherited object keys", async () => {
  const payload = await postedPayload({
    category: "constructor",
    message: "hi",
    deviceModel: "__proto__",
    osVersion: "17",
  });
  const embed = payload.embeds[0];
  assert.equal(embed.title, "💬 OTHER");
  assert.equal(embed.color, 0x95a5a6);
  assert.equal(field(payload, "Device"), "\\_\\_proto\\_\\_ · 17");
});

test("a known device id still gets its friendly name, looked up by the raw id", async () => {
  const payload = await postedPayload({
    category: "praise",
    message: "love it",
    deviceModel: "iPhone17,1",
    osVersion: "17.5",
  });
  assert.equal(payload.embeds[0].title, "💚 PRAISE");
  assert.equal(field(payload, "Device"), "iPhone17,1 (iPhone 16 Pro) · 17.5");
});

test("an oversized message is cut to the embed's budget", async () => {
  const payload = await postedPayload({
    category: "bug",
    message: "m".repeat(10000),
  });
  const description = payload.embeds[0].description;
  assert.equal(description.length, 3000);
  assert.ok(description.endsWith("…"));
});

test("a document with no data posts nothing", async () => {
  const calls = await runWith(undefined);
  assert.equal(calls.length, 0);
});

test("a webhook failure is logged rather than thrown", async () => {
  await runWith(
    { category: "bug", message: "hi" },
    { respond: () => ({ ok: false, status: 500, text: async () => "boom" }) },
  );
  await runWith(
    { category: "bug", message: "hi" },
    { respond: () => { throw new Error("network down"); } },
  );
});
