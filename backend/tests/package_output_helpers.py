"""Make old synthetic adapter envelopes obey the new OUTPUT spelling.

This helper never validates/repairs a deliberately invalid answer or quote.
Only pre-existing Pydantic defaults are filled for complete strict wire fixtures.
Production decoding and all original rejection assertions remain authoritative.
"""
import copy
import json
import math

from schulpilot import graphic_transport, package_output_transport
from schulpilot.schemas import PackageOutput


class PackageOutputCapture:
    def __init__(self, monkeypatch):
        self.binding = None
        self.graphic_binding = None
        original_graphics = graphic_transport.bind

        def capture_graphics(schema):
            self.graphic_binding = original_graphics(schema)
            return self.graphic_binding

        monkeypatch.setattr(graphic_transport, "bind", capture_graphics)
        original = package_output_transport.bind
        def capture(schema):
            self.binding = original(schema)
            return self.binding
        monkeypatch.setattr(package_output_transport, "bind", capture)

    def schema(self, actual):
        if self.binding is None:
            if self.graphic_binding is not None:
                assert actual == self.graphic_binding.wire_schema
                return self.graphic_binding.canonical_schema
            return actual
        assert actual == self.binding.wire_schema
        return self.binding.canonical_schema

    def wire(self, value):
        if self.binding is None or not isinstance(value, dict) or "units" not in value:
            result = copy.deepcopy(value)
            if self.graphic_binding is not None:
                # Emit the requested native spelling, including deliberately
                # invalid pairs. No repaired parameters or pre-billing reject.
                def native(item):
                    if isinstance(item, dict):
                        presentation = item.get("presentation")
                        if isinstance(presentation, dict):
                            for block in presentation.get("blocks", []):
                                if isinstance(block, dict) and block.get("kind") == "fraction":
                                    values = block.get("numbers")
                                    if isinstance(values, list):
                                        values = [int(v) if type(v) is float and math.isfinite(v) and v.is_integer() else v for v in values]
                                        block["numbers"] = json.dumps(values, separators=(",", ":"))
                        for child in item.values():
                            native(child)
                    elif isinstance(item, list):
                        for child in item:
                            native(child)
                native(result)
            return result
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
