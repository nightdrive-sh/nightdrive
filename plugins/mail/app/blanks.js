.pragma library

// A plain-text message's blank lines tidied for reading (#3318). Newsletters' text parts come out of HTML with long
// runs of empty lines, lines of only NBSP, and a "preheader" of invisible filler (U+034F, U+00AD, U+2007, NBSP over
// and over) that is meant to pad the inbox's preview. A line of only whitespace and invisible characters counts as
// blank: each run of them becomes one empty line, and those at the start and end go. Other lines stay as they are,
// trailing spaces too ("-- " is a signature's separator), and quoted "> " lines aren't blank, so a quote keeps its shape.
// The same rule is lib/blanks.py's (the reply's quote); blanks_test.py tests both on the same cases.

// Whitespace (\s has NBSP, U+2000–U+200A, U+202F, U+3000, U+FEFF) and the characters that draw nothing: soft hyphen,
// combining grapheme joiner, zero-width and direction marks, word joiner and its kin, Hangul fillers.
const BLANK = /^[\s­͏؜ᅟᅠ឴឵᠎​-‏‪-‮⁠-⁯ㅤﾠ]*$/

function tidy(t) {
    const out = []
    for (const line of t.split(/\r?\n/)) {
        if (!BLANK.test(line)) out.push(line)
        else if (out.length > 0 && out[out.length - 1] !== "") out.push("")
    }
    if (out.length > 0 && out[out.length - 1] === "") out.pop()
    return out.join("\n")
}
