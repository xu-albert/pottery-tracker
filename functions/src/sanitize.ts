// Discord renders embed text as markdown, so every character a reporter types
// is potential formatting: backticks break out of the code span the uid sits
// in, `[text](url)` becomes a clickable link, and `#`/`>`/`-` at the start of a
// line become headings, quotes and lists. Escaping (rather than stripping)
// keeps the report readable while making it inert.
const MARKDOWN_CONTROL = /[\\`*_~|>#[\]()-]/g;

// C0 controls, zero-width characters and bidi overrides: invisible in the
// channel, and the bidi ones can reorder text into something it is not.
// eslint-disable-next-line no-control-regex
const INVISIBLE =
  /[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f\u200b-\u200f\u202a-\u202e\u2066-\u2069]/g;

/**
 * Makes a client-supplied string safe to drop into a Discord embed: no
 * formatting, no invisible characters, and within the field's length budget.
 *
 * Truncation happens last so the escaped result — not the raw input — is what
 * has to fit, and a trailing lone backslash from an unlucky cut is dropped
 * rather than left to escape the ellipsis.
 *
 * Mentions are handled separately, by `allowed_mentions` on the payload: a
 * backslash does not neutralise `@everyone`, and an unsendable ping is a
 * property of the request, not of the text.
 */
export function safeText(value: string, max: number): string {
  const escaped = value
    .replace(INVISIBLE, "")
    .replace(MARKDOWN_CONTROL, (c) => `\\${c}`);
  if (escaped.length <= max) return escaped;
  return escaped.slice(0, max - 1).replace(/\\+$/, "") + "…";
}
