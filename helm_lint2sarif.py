import sys
import json
import re

sarif = {
    "version": "2.1.0",
    "runs": [
        {
            "tool": {
                "driver": {
                    "name": "helm lint",
                    "informationUri": "https://helm.sh/docs/helm/helm_lint/",
                }
            },
            "results": [],
        }
    ],
}

lint_regex = re.compile(
    r"\[(?P<level>ERROR|WARNING|INFO)\]\s+(?P<file>[^:]+):(?P<message>.*)"
)

for line in sys.stdin:
    match = lint_regex.match(line)
    if match:
        level = match.group("level").lower()
        file = match.group("file").strip()
        message = match.group("message").strip()
        sarif["runs"][0]["results"].append(
            {
                "level": level,
                "message": {"text": message},
                "locations": [
                    {"physicalLocation": {"artifactLocation": {"uri": file}}}
                ],
            }
        )

json.dump(sarif, sys.stdout, indent=2)
