// The Markdown Claude writes, as HTML for a session's own view (detail.js): headings, paragraphs, lists, quotes, fenced
// code, pipe tables, and inline code, bold, italic and links. Not a full CommonMark: what Claude's replies use.
// Safe by construction: every piece of text goes through esc() first, and only the tags made here are added; a link is
// one only when it is http(s), and opens outside the app.
import { esc } from "./api.js";

const FENCE = /^\s*(```|~~~)/;
const BULLET = /^(\s*)[-*+]\s+(.*)$/;
const NUMBERED = /^(\s*)\d+[.)]\s+(.*)$/;
const HEADING = /^(#{1,6})\s+(.*)$/;
const TABLE_RULE = /^\s*\|?\s*:?-{2,}:?\s*(\|\s*:?-{2,}:?\s*)*\|?\s*$/;

// Inline marks on one line of text. Code spans are taken out first, so nothing inside them is touched.
function inline(text) {
  const codes = [];
  let s = text.replace(/`([^`]+)`/g, (_, c) => `\u0000${codes.push(c) - 1}\u0000`);
  s = esc(s)
    .replace(/\[([^\]]+)\]\((https?:\/\/[^\s)]+)\)/g,
             (_, t, url) => `<a href="${url}" target="_blank" rel="noopener noreferrer">${t}</a>`)
    .replace(/\*\*([^*]+)\*\*/g, "<b>$1</b>")
    .replace(/(^|[^\w*])\*([^*\s][^*]*)\*(?!\w)/g, "$1<i>$2</i>")
    .replace(/(^|[^\w])_([^_\s][^_]*)_(?!\w)/g, "$1<i>$2</i>");
  return s.replace(/\u0000(\d+)\u0000/g, (_, i) => `<code>${esc(codes[i])}</code>`);
}

function cells(line) {
  return line.trim().replace(/^\|/, "").replace(/\|$/, "").split("|").map(c => inline(c.trim()));
}

function table(rows) {
  const [head, , ...body] = rows;
  return `<table><thead><tr>${cells(head).map(c => `<th>${c}</th>`).join("")}</tr></thead><tbody>` +
    body.map(r => `<tr>${cells(r).map(c => `<td>${c}</td>`).join("")}</tr>`).join("") + "</tbody></table>";
}

// One list, its items by their own marker; a deeper indent goes into the item above it
function list(lines, at) {
  const own = BULLET.test(lines[at]) ? BULLET : NUMBERED;    // a list of the other kind next to it is a list of its own
  const first = lines[at].match(own);
  const tag = own === BULLET ? "ul" : "ol";
  const indent = first[1].length;
  const items = [];
  let i = at;
  while (i < lines.length) {
    const m = lines[i].match(BULLET) || lines[i].match(NUMBERED);
    if (!m) break;
    if (m[1].length > indent && items.length) {
      const [html, next] = list(lines, i);
      items[items.length - 1] += html;
      i = next;
      continue;
    }
    if (m[1].length < indent || !own.test(lines[i])) break;
    items.push(inline(m[2]));
    i++;
  }
  return [`<${tag}>${items.map(t => `<li>${t}</li>`).join("")}</${tag}>`, i];
}

export function markdown(text) {
  const lines = String(text ?? "").replace(/\r/g, "").split("\n");
  const out = [];
  let i = 0;
  while (i < lines.length) {
    const line = lines[i];
    if (!line.trim()) { i++; continue; }
    if (FENCE.test(line)) {
      const close = line.trim().slice(0, 3);
      const code = [];
      for (i++; i < lines.length && !lines[i].trim().startsWith(close); i++) code.push(lines[i]);
      i++;
      out.push(`<pre><code>${esc(code.join("\n"))}</code></pre>`);
      continue;
    }
    const h = line.match(HEADING);
    if (h) { out.push(`<h${Math.min(h[1].length + 2, 6)}>${inline(h[2])}</h${Math.min(h[1].length + 2, 6)}>`); i++; continue; }
    if (line.includes("|") && TABLE_RULE.test(lines[i + 1] || "")) {
      const rows = [];
      for (; i < lines.length && lines[i].includes("|"); i++) rows.push(lines[i]);
      out.push(table(rows));
      continue;
    }
    if (BULLET.test(line) || NUMBERED.test(line)) {
      const [html, next] = list(lines, i);
      out.push(html);
      i = next;
      continue;
    }
    if (/^\s*>/.test(line)) {
      const quote = [];
      for (; i < lines.length && /^\s*>/.test(lines[i]); i++) quote.push(lines[i].replace(/^\s*>\s?/, ""));
      out.push(`<blockquote>${markdown(quote.join("\n"))}</blockquote>`);
      continue;
    }
    if (/^\s*([-*_])(\s*\1){2,}\s*$/.test(line)) { out.push("<hr>"); i++; continue; }
    // A paragraph: lines until a blank one or another block; a single line break stays one
    const para = [];
    for (; i < lines.length && lines[i].trim() && !FENCE.test(lines[i]) && !HEADING.test(lines[i]) &&
           !BULLET.test(lines[i]) && !NUMBERED.test(lines[i]) && !/^\s*>/.test(lines[i]); i++) para.push(inline(lines[i]));
    out.push(`<p>${para.join("<br>")}</p>`);
  }
  return out.join("");
}
