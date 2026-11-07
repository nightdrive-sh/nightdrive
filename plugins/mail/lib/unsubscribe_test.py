#!/usr/bin/env python3
"""How Mail finds a newsletter's unsubscribe link (#2393): `python3 plugins/mail/lib/unsubscribe_test.py`.
The List-Unsubscribe header first (https over mailto), then a link in the body that says it in one language or another,
by its own text, its address or the text before it; never a javascript: or file: link, and nothing in a mail that
isn't a newsletter."""

import email.policy
import sys
import unittest
from email.message import EmailMessage
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import unsubscribe  # noqa: E402
from unsubscribe import find, from_header, from_html, from_text  # noqa: E402


def mail(html=None, text=None, **headers):
    msg = EmailMessage(policy=email.policy.default)
    msg["From"] = "News <news@shop.example>"
    msg["Subject"] = "This week"
    for k, v in headers.items():
        msg[k.replace("_", "-")] = v
    if text is not None:
        msg.set_content(text)
    if html is not None:
        if text is None:
            msg.set_content(html, subtype="html")
        else:
            msg.add_alternative(html, subtype="html")
    return msg


class Header(unittest.TestCase):
    def test_https_preferred_over_mailto(self):
        got = from_header("<mailto:leave@list.example?subject=unsub>, <https://list.example/u/42>")
        self.assertEqual(got, {"url": "https://list.example/u/42", "kind": "web", "from": "header"})

    def test_mailto_alone(self):
        got = from_header("<mailto:leave@list.example?subject=unsubscribe>")
        self.assertEqual(got["kind"], "mail")
        self.assertEqual(got["url"], "mailto:leave@list.example?subject=unsubscribe")

    def test_folded_entry(self):
        self.assertEqual(from_header("<https://list.example/u/\n 42?x=1>")["url"], "https://list.example/u/42?x=1")

    def test_mailto_over_http(self):
        self.assertEqual(from_header("<http://list.example/u>, <mailto:a@b.example>")["kind"], "mail")

    def test_other_schemes_never(self):
        self.assertIsNone(from_header("<javascript:alert(1)>, <file:///etc/passwd>"))
        self.assertIsNone(from_header(""))

    def test_header_wins_over_body(self):
        msg = mail(html='<a href="https://shop.example/body-unsub">Unsubscribe</a>',
                   List_Unsubscribe="<https://shop.example/header-unsub>")
        self.assertEqual(find(msg)["url"], "https://shop.example/header-unsub")


class Html(unittest.TestCase):
    def test_link_text(self):
        html = '<p>Hello</p><a href="https://shop.example/sale">Sale</a> <a href="https://shop.example/x?t=1">Unsubscribe</a>'
        self.assertEqual(from_html(html), {"url": "https://shop.example/x?t=1", "kind": "web", "from": "body"})

    def test_languages(self):
        for words in ("Peruuta tilaus", "Peruuta uutiskirje", "Lopeta tilaus", "peruuttaa uutiskirjeen tilauksen",
                      "Avsluta prenumeration", "Abmelden", "Newsletter abbestellen", "Se désabonner",
                      "Darse de baja", "Uitschrijven", "Meld deg av"):
            with self.subTest(words=words):
                html = f'<a href="https://shop.example/home">Shop</a><a href="https://shop.example/q">{words}</a>'
                self.assertEqual(from_html(html)["url"], "https://shop.example/q")

    def test_address_says_it(self):
        html = '<a href="https://shop.example/">Shop</a> <a href="https://mail.shop.example/unsubscribe/9">here</a>'
        self.assertEqual(from_html(html)["url"], "https://mail.shop.example/unsubscribe/9")

    def test_nearby_text(self):
        html = ('<a href="https://shop.example/read">Read more</a><p>Jos et halua enää uutiskirjettä, voit '
                '<b>peruuttaa tilauksen</b> <a href="https://shop.example/p/7">tästä</a>.</p>')
        self.assertEqual(from_html(html)["url"], "https://shop.example/p/7")

    def test_sentence_before(self):
        html = ('<a href="https://k.example/read">Lue lisää</a> <p>Jos et halua enää vastaanottaa tätä tiedotetta, '
                '<a href="https://k.example/o/1">klikkaa tästä</a></p>')
        self.assertEqual(from_html(html)["url"], "https://k.example/o/1")

    def test_own_text_beats_nearby(self):
        html = ('<p>Unsubscribe or <a href="https://shop.example/prefs">change settings</a></p>'
                '<a href="https://shop.example/bye">Unsubscribe</a>')
        self.assertEqual(from_html(html)["url"], "https://shop.example/bye")

    def test_mailto_in_body(self):
        html = '<a href="mailto:off@shop.example?subject=Unsubscribe">Unsubscribe</a>'
        self.assertEqual(from_html(html)["kind"], "mail")

    def test_javascript_never(self):
        self.assertIsNone(from_html('<a href="javascript:go()">Unsubscribe</a>'))

    def test_style_text_isnt_words(self):
        html = '<style>.unsubscribe{color:red}</style><a href="https://shop.example/a">Read</a>'
        self.assertIsNone(from_html(html))

    def test_ordinary_mail(self):
        self.assertIsNone(from_html('<p>See <a href="https://example.com/doc">the doc</a>.</p>'))

    def test_broken_html(self):
        self.assertEqual(from_html('<a href="https://x.example/u">Unsubscribe</a><a href="')["url"],
                         "https://x.example/u")


class Text(unittest.TestCase):
    def test_same_line(self):
        t = "Hi!\n\nRead: https://shop.example/read\n\nUnsubscribe: https://shop.example/u/1.\n"
        self.assertEqual(from_text(t)["url"], "https://shop.example/u/1")

    def test_line_after(self):
        t = "Hei!\n\nPeruuta tilaus tästä:\nhttps://shop.example/p/2\n"
        self.assertEqual(from_text(t)["url"], "https://shop.example/p/2")

    def test_ordinary(self):
        self.assertIsNone(from_text("See https://example.com/doc\nThanks"))

    def test_plain_message(self):
        msg = mail(text="News\n\nTo unsubscribe, visit https://shop.example/u/3\n")
        self.assertEqual(find(msg)["url"], "https://shop.example/u/3")

    def test_none_in_plain_reply(self):
        self.assertIsNone(find(mail(text="Shall we meet at 10? https://maps.example/x")))


class Html_and_text(unittest.TestCase):
    def test_html_part_read(self):
        msg = mail(text="News", html='<a href="https://shop.example/u/4">Unsubscribe</a>')
        self.assertEqual(find(msg)["url"], "https://shop.example/u/4")


class Kinds(unittest.TestCase):
    def test_kind(self):
        self.assertEqual(unsubscribe.kind("HTTPS://a.example/"), "web")
        self.assertEqual(unsubscribe.kind("mailto:a@b.example"), "mail")
        self.assertIsNone(unsubscribe.kind("https://"))
        self.assertIsNone(unsubscribe.kind("ftp://a.example/"))


if __name__ == "__main__":
    unittest.main()
