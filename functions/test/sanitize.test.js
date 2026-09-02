// Run with `npm test` in functions/ (compiles src/ first, then runs these
// against the emitted JS with Node's built-in test runner — no extra deps).
const test = require("node:test");
const assert = require("node:assert/strict");

const { safeText } = require("../lib/sanitize");

test("plain text is passed through unchanged", () => {
  assert.equal(
    safeText("The lid cracked in the bisque fire.", 100),
    "The lid cracked in the bisque fire.",
  );
});

test("markdown control characters are escaped, not interpreted", () => {
  assert.equal(
    safeText("[click](https://evil.test)", 200),
    "\\[click\\]\\(https://evil.test\\)",
  );
  assert.equal(safeText("**urgent**", 200), "\\*\\*urgent\\*\\*");
  assert.equal(safeText("~~struck~~", 200), "\\~\\~struck\\~\\~");
  assert.equal(safeText("||spoiler||", 200), "\\|\\|spoiler\\|\\|");
});

test("a backtick cannot break out of the uid code span", () => {
  // The uid renders as `${uid}`; an unescaped backtick would close the span
  // and let everything after it render as markdown.
  const rendered = "`" + safeText("abc`**owned**", 200) + "`";
  assert.equal(rendered, "`abc\\`\\*\\*owned\\*\\*`");
});

test("headings, quotes and lists cannot be injected", () => {
  assert.equal(safeText("# BIG", 50), "\\# BIG");
  assert.equal(safeText("> quoted", 50), "\\> quoted");
  assert.equal(safeText("- item", 50), "\\- item");
});

test("invisible and bidi characters are removed", () => {
  const zeroWidthSpace = "\u200b";
  const rightToLeftOverride = "\u202e";
  const nul = "\u0000";
  assert.equal(
    safeText(`a${zeroWidthSpace}b${rightToLeftOverride}c${nul}d`, 50),
    "abcd",
  );
});

test("output is truncated to the caller's budget", () => {
  const out = safeText("x".repeat(500), 64);
  assert.equal(out.length, 64);
  assert.ok(out.endsWith("…"));
});

test("escaping is counted before truncation, so the budget is real", () => {
  // Every backtick escapes to two characters: capping the input instead of the
  // output would emit 200 characters where 64 were asked for.
  const out = safeText("`".repeat(100), 64);
  assert.ok(out.length <= 64, `got ${out.length}`);
});

test("truncation never leaves a dangling escape", () => {
  for (let max = 4; max < 40; max++) {
    const out = safeText("`".repeat(100), max);
    assert.ok(out.length <= max, `too long at max=${max}`);
    assert.ok(!out.endsWith("\\…"), `dangling escape at max=${max}: ${out}`);
  }
});
