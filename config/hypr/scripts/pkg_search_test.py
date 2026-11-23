#!/usr/bin/env python3
"""pkg-search (#2647): Fedora's desktop apps count as apps, with Fedora's AppStream catalog and without it, and the tools
leave libraries out but not apps whose name starts with lib: `python3 config/hypr/scripts/pkg_search_test.py`.
dnf, flatpak and rpm are stubs; the catalog is a throwaway folder."""

import gzip
import os
import tempfile
import unittest
from importlib.machinery import SourceFileLoader
from importlib.util import module_from_spec, spec_from_loader
from pathlib import Path
from unittest import mock

HERE = Path(__file__).resolve().parent
loader = SourceFileLoader("pkg_search", str(HERE / "pkg-search"))
ps = module_from_spec(spec_from_loader("pkg_search", loader))
loader.exec_module(ps)

# dnf repoquery: the search's packages, and (--whatprovides application()) those with a desktop file, as dnf5 prints
# %{provides}: the first after the name, the rest one per line
DNF = r"""#!/bin/sh
case "$*" in
*whatprovides*) printf '%s\n' 'libreoffice-writer|application()' 'application(libreoffice-writer.desktop)' \
    'ghostwriter|application()' 'application(org.kde.ghostwriter.desktop)' 'metainfo()' ;;
*) printf '%s\n' 'libreoffice-writer|LibreOffice Word Processor Application' 'ghostwriter|Markdown editor' \
    'libwriter|A library' 'libwriter-devel|Its headers' 'libreoffice-help-en-GB|Help' 'writerperfect|Import filters' ;;
esac
"""
FLATPAK = """#!/bin/sh
[ "$1" = search ] && printf 'org.kde.ghostwriter\\tghostwriter\\tMarkdown editor\\tflathub\\n'
"""
CATALOG = """<components>
<component type="desktop-application"><id>libreoffice-writer.desktop</id><pkgname>libreoffice-writer</pkgname>
<name>LibreOffice Writer</name><summary>Create and edit text documents</summary></component>
</components>"""


class Search(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        t = Path(self.tmp.name)
        for name, text in (("dnf", DNF), ("flatpak", FLATPAK), ("rpm", "#!/bin/sh\n")):
            (t / name).write_text(text)
            (t / name).chmod(0o755)
        self.catalog = t / "swcatalog"
        patches = [mock.patch.dict(os.environ, {"PATH": f"{t}:{os.environ['PATH']}"}),
                   mock.patch.object(ps, "SWCATALOG", str(self.catalog)), mock.patch.object(ps, "CACHE", str(t / "cache.json"))]
        for p in patches:
            p.start()
            self.addCleanup(p.stop)

    def tearDown(self):
        self.tmp.cleanup()

    def apps(self):
        out = ps.main("writer")
        return {r["id"]: r for r in out["apps"]}, [r["id"] for r in out["tools"]]

    def test_with_the_catalog_writer_is_an_app_by_its_name(self):
        (self.catalog / "xml").mkdir(parents=True)
        with gzip.open(self.catalog / "xml/fedora.xml.gz", "wt") as fh:
            fh.write(CATALOG)
        apps, _ = self.apps()
        self.assertEqual(apps["libreoffice-writer"]["name"], "LibreOffice Writer")
        self.assertEqual(apps["libreoffice-writer"]["src"], "dnf")

    def test_without_the_catalog_a_desktop_file_makes_it_an_app(self):
        apps, tools = self.apps()
        self.assertIn("libreoffice-writer", apps)
        self.assertNotIn("libreoffice-writer", tools)
        # Fedora's and Flathub's ghostwriter are one row: Fedora's, named by Flathub, Flathub's as the alternative
        self.assertEqual(apps["ghostwriter"]["name"], "ghostwriter")
        self.assertEqual(apps["ghostwriter"]["alt"], {"src": "flatpak", "id": "org.kde.ghostwriter"})
        self.assertNotIn("org.kde.ghostwriter", apps)
        self.assertTrue(all("bare" not in r for r in apps.values()))

    def test_tools_leave_libraries_and_help_out(self):
        _, tools = self.apps()
        self.assertEqual(tools, ["writerperfect"])


class NotTools(unittest.TestCase):
    def test_libraries_but_not_apps_named_lib(self):
        for name in ("libpng", "libX11", "libxml2", "libwriter-devel", "libvirt-libs", "libreoffice-help-en-GB",
                     "libreoffice-langpack-fi", "python3-foo"):
            self.assertTrue(ps.NOT_TOOLS.search(name), name)
        for name in ("libreoffice-writer", "libvirt-client", "libinput-utils", "ripgrep"):
            self.assertFalse(ps.NOT_TOOLS.search(name), name)


if __name__ == "__main__":
    unittest.main()
