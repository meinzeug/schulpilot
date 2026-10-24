"""Make old synthetic adapter envelopes obey the new OUTPUT spelling.

This helper never validates/repairs a deliberately invalid answer or quote.
Only pre-existing Pydantic defaults are filled for complete strict wire fixtures.
Production decoding and all original rejection assertions remain authoritative.
"""
import copy
import json

from schulpilot import package_output_transport
from schulpilot.schemas import PackageOutput


class PackageOutputCapture:
    def __init__(self, monkeypatch):
        self.binding = None
        original = package_output_transport.bind
        def capture(schema):
            self.binding = original(schema)
            return self.binding
        monkeypatch.setattr(package_output_transport, "bind", capture)

    def schema(self, actual):
        if self.binding is None:
            return actual
        assert actual == self.binding.wire_schema
        return self.binding.canonical_schema

    def wire(self, value):
        if self.binding is None or not isinstance(value, dict) or "units" not in value:
            return copy.deepcopy(value)
        root = PackageOutput.model_json_schema()
        def defaults(schema, item):
            if "$ref" in schema:
                return defaults(root["$defs"][schema["$ref"].rsplit("/", 1)[-1]], item)
            if "anyOf" in schema:
                branch = next((branch for branch in schema["anyOf"] if (item is None) == (branch.get("type") == "null")), {})
                return defaults(branch, item)
            if isinstance(item, dict):
                result = copy.deepcopy(item)
                for key, child in schema.get("properties", {}).items():
                    if key not in result and "default" in child:
                        result[key] = copy.deepcopy(child["default"])
                    if key in result:
                        result[key] = defaults(child, result[key])
                return result
            if isinstance(item, list):
                return [defaults(schema.get("items", {}), child) for child in item]
            return item
        def rename(item):
            if isinstance(item, list):
                return [rename(child) for child in item]
            if not isinstance(item, dict):
                return item
            result = {}
            for key, child in item.items():
                if key in self.binding.constants and json.dumps(child, sort_keys=True) == json.dumps(self.binding.constants[key], sort_keys=True):
                    continue
                alias = self.binding.aliases.get(key, key)
                assert alias not in result
                result[alias] = rename(child)
            return result
        return rename(defaults(root, value))
