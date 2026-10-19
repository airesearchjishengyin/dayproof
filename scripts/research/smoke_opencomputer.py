"""Reproduce the limited offline OpenComputer investigation (Python >= 3.10).

Downloads a reviewed module at an immutable commit into a temporary directory,
checks its digest, and executes only its offline methods on synthetic input.
No upstream source is vendored or installed. Network is used only to fetch the
module. This is not a complete ODT-format, GUI, cloud, or LLM integration test.
"""

import hashlib
import json
from pathlib import Path
import re
import runpy
import sys
import tempfile
import urllib.request
import zipfile

SOURCE = (
    "https://raw.githubusercontent.com/echo0715/OpenComputer/"
    "76c5ec32221045a68c4ca47a799e0abc4b303d6a/"
    "verifiers/libreoffice_writer/libreoffice_writer.py"
)
DIGEST = "83215f785f996f0fcf74b49ec35e4caa8fc0da62804d1352e8fa2e5edf7e2f5e"
XML = """<?xml version="1.0" encoding="UTF-8"?>
<office:document-content
 xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0"
 xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0"
 xmlns:table="urn:oasis:names:tc:opendocument:xmlns:table:1.0">
 <office:body><office:text>
 <text:h text:outline-level="1">技术方案</text:h>
 <text:p>实施步骤：先部署测试环境，再运行验收。</text:p>
 <table:table table:name="Actions"><table:table-row><table:table-cell>
 <text:p>负责人：Alice</text:p>
 </table:table-cell></table:table-row></table:table>
 </office:text></office:body>
</office:document-content>"""
XML = re.sub(r">\s+<", "><", XML)


def main():
    if sys.version_info < (3, 10):
        raise SystemExit("Python >= 3.10 required by the upstream module")
    request = urllib.request.Request(SOURCE, headers={"User-Agent": "Dayproof-research/0.1"})
    with urllib.request.urlopen(request, timeout=30) as response:
        source = response.read(256_000)
    if hashlib.sha256(source).hexdigest() != DIGEST:
        raise SystemExit("Source digest mismatch; refusing execution")
    with tempfile.TemporaryDirectory(prefix="dayproof-verifier-smoke-") as temporary:
        root = Path(temporary)
        module = root / "writer.py"
        module.write_bytes(source)
        namespace = runpy.run_path(str(module), run_name="reviewed_research_module")
        verifier = namespace["LibreOfficeWriterVerifier"]()
        document = root / "meeting.odt"
        with zipfile.ZipFile(document, "w") as archive:
            archive.writestr("mimetype", "application/vnd.oasis.opendocument.text")
            archive.writestr("content.xml", XML)
        text = verifier.parse_file_text(str(document))
        paragraphs = verifier.parse_file_paragraphs(str(document))
        tables = verifier.parse_file_tables(str(document))
        missing = verifier.check_file_exists(str(root / "missing.odt"))
        broken = root / "broken.odt"
        broken.write_text("not a ZIP", encoding="utf-8")
        corrupt = verifier.parse_file_text(str(broken))
        checks = {
            "offline_text_extracts_body": "实施步骤" in text.get("text", ""),
            "offline_paragraphs_preserve_heading_order": (
                paragraphs.get("paragraphs", [{}])[0].get("text") == "技术方案"
            ),
            "offline_tables_extract_owner": (
                tables.get("tables", [{}])[0].get("data") == [["负责人：Alice"]]
            ),
            "missing_file_not_exists": missing.get("exists") is False,
            "corrupt_file_returns_error": "error" in corrupt,
        }
        if not all(checks.values()):
            raise SystemExit(json.dumps(checks, ensure_ascii=False))
        result = {
            "date": "2026-10-19",
            "python": f"{sys.version_info.major}.{sys.version_info.minor}",
            "source": SOURCE,
            "source_sha256": DIGEST,
            "scope": (
                "Offline methods on a synthetic minimal ODT XML ZIP; no GUI, "
                "UNO, E2B or LLM integration. No network during verifier execution."
            ),
            "checks": checks,
            "observed_limitations": {
                "parse_file_text_moves_heading_after_body": (
                    text["text"].index("技术方案") > text["text"].index("实施步骤")
                ),
                "parse_file_text_omits_table_cell": "Alice" not in text["text"],
            },
            "extract": text["text"],
            "paragraphs": paragraphs["paragraphs"],
            "tables": tables["tables"],
        }
        print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
