"""Reproduce two narrow OfficeBench evaluator behaviours with stdlib only.

Fetches a pinned source, verifies its digest, then extracts four reviewed
functions via AST. Does not import OfficeBench or run its environment. The
examples demonstrate function semantics, not a full benchmark exploit.
"""

import ast
import contextlib
import hashlib
import io
import json
import os
from pathlib import Path
import tempfile
import urllib.request

SOURCE = (
    "https://raw.githubusercontent.com/zlwang-cs/OfficeBench/"
    "b978b808667c32b52ce19a67ce1def1de9ae02b7/utils/evaluate.py"
)
DIGEST = "f4a675a590a57844fd21d6d6660a00d8c69661b0f92dc26146f9b8869a26cc90"
FUNCTIONS = {
    "_is_number", "_evaluate_contain_text", "evaluate_contain", "evaluate_not_contain"
}


def main():
    request = urllib.request.Request(SOURCE, headers={"User-Agent": "Dayproof-research/0.1"})
    with urllib.request.urlopen(request, timeout=30) as response:
        source = response.read(100_000)
    if hashlib.sha256(source).hexdigest() != DIGEST:
        raise SystemExit("Source digest mismatch")
    tree = ast.parse(source)
    selected = [n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name in FUNCTIONS]
    if {n.name for n in selected} != FUNCTIONS:
        raise SystemExit("Expected functions missing")
    namespace = {"os": os}
    exec(compile(ast.Module(body=selected, type_ignores=[]), SOURCE, "exec"), namespace)
    with tempfile.TemporaryDirectory(prefix="dayproof-officebench-") as directory:
        args = {"doc_type": "txt", "file": "missing.txt", "keywords": ["secret"]}
        with contextlib.redirect_stdout(io.StringIO()):
            missing_passes = namespace["evaluate_not_contain"](directory, args)
        negative = "There is no implementation plan and no acceptance test."
        args = {"doc_type": "txt", "file": "negative.txt", "keywords": ["implementation plan", "acceptance test"]}
        Path(directory, "negative.txt").write_text(negative)
        keywords_pass = namespace["evaluate_contain"](directory, args)
    assert missing_passes is True
    assert keywords_pass is True
    print(json.dumps({
        "date": "2026-10-19",
        "source": SOURCE,
        "source_sha256": DIGEST,
        "scope": "Four AST-extracted upstream functions; synthetic TXT inputs; no app, email, model or full-suite run.",
        "observed_behaviours": {
            "missing_file_passes_not_contain_in_isolation": missing_passes,
            "negated_requirements_pass_literal_keywords": keywords_pass,
        },
        "negative_input": negative,
        "interpretation": "Require a separate file/readability check; substring matching proves lexical presence only. A composed upstream task may already add other checks.",
    }, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
