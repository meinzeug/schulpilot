"""Untrusted candidate subprocess: bounded primitive RPC, no test/report access."""

import json
import sys

from schulpilot import instructional_decisions as decisions


def main():
    value = json.loads(sys.stdin.buffer.read(65537))
    if value["method"] == "schema":
        schema = decisions.DecisionOutput.model_json_schema()
        decisions.schema_refs(schema, value["payload"])
        answer = {"schema": schema}
    elif value["method"] == "validate":
        try:
            decisions.validate(value["plan"], value["payload"])
            answer = {"valid": True}
        except decisions.DecisionPlanError as error:
            answer = {"valid": False, "code": error.code}
    else:
        raise ValueError("method")
    sys.stdout.write(json.dumps(answer))


if __name__ == "__main__":
    main()
