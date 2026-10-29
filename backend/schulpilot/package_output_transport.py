"""Request-bound, reversible package output spelling, never a saved format.

Property names, proven scalar constants and exact-size arrays change on the wire.
Strings, answers, source excerpts, list order and numeric values are untouched.
The caller must run every existing canonical validator after decoding.
"""
import copy
import json
import math
import string
from dataclasses import dataclass

REVISION = "package-output-1"
ARRAY_REVISION = "package-fixed-arrays-1"
_KEEP = {"id", "type", "kind", "group_id", "subject"}
_MISSING = object()


def _json(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False)


def _nodes(value):
    if isinstance(value, dict):
        yield value
        for key in ("properties", "$defs", "definitions"):
            for child in value.get(key, {}).values():
                yield from _nodes(child)
        for key in ("items", "additionalProperties"):
            yield from _nodes(value.get(key))
        for key in ("anyOf", "oneOf", "allOf"):
            for child in value.get(key, []):
                yield from _nodes(child)


def _literal(node):
    value = node.get("const", _MISSING)
    if value is _MISSING and len(node.get("enum", [])) == 1:
        value = node["enum"][0]
    if node.get("type") == "null":
        value = None
    # No generated table, copied prose or guessed default. Only an explicit
    # single scalar/null outcome in EVERY schema occurrence is reconstructible.
    return value if value is None or type(value) in (bool, str, int, float) else _MISSING


def _alias(index):
    alphabet = string.ascii_letters
    result = ""
    while True:
        result = alphabet[index % len(alphabet)] + result
        index = index // len(alphabet) - 1
        if index < 0:
            return result


def _same(a, b):
    return _json(a) == _json(b)


def _fixed_array_size(node):
    """Only exact cardinalities become closed objects; never guess defaults."""
    size = node.get("minItems")
    if (node.get("type") == "array" and type(size) is int and 1 <= size <= 8
            and node.get("maxItems") == size and isinstance(node.get("items"), dict)
            and "enum" not in node and "const" not in node):
        return size
    return None


def _enum_same(value, allowed):
    # JSON Schema equates finite JSON numbers (1 and1.0), including inside
    # numeric parameter arrays. Do not normalize data/constants or relax the
    # separate strict integer/Choice type check; bool is never a number.
    if isinstance(value, list) and isinstance(allowed, list):
        def number(item):
            return type(item) is int or type(item) is float and math.isfinite(item)

        if all(number(item) for item in [*value, *allowed]):
            return len(value) == len(allowed) and all(a == b for a, b in zip(value, allowed, strict=True))
    return _same(value, allowed)


@dataclass(frozen=True)
class Binding:
    canonical_schema: dict
    wire_schema: dict
    aliases: dict
    constants: dict

    @property
    def rules(self):
        names = {alias: name for name, alias in self.aliases.items() if name not in self.constants}
        return ("\n" + REVISION + ": Output property aliases=" + _json(names)
                + ". These replace PROPERTY NAMES only, including nested objects; string/enum values, "
                "answers, literal quotes and array order remain unchanged. Schema-omitted constants are "
                "reconstructed by the server; never output their aliases. " + ARRAY_REVISION +
                ": Some exact-length lists are objects with required keys v0, v1, etc. "
                "Fill each key once in order, exactly as specified by its schema. "
                "No compressed data or executable code.")

    def encode(self, canonical):
        """Synthetic adapters/tests can emit the exact newly requested format."""
        _json(canonical)
        return self._walk(self.canonical_schema, canonical, encoding=True)

    def decode(self, wire):
        _json(wire)
        return self._walk(self.canonical_schema, wire, encoding=False)

    def _walk(self, node, value, *, encoding, depth=0):
        if depth > 80:
            raise ValueError("Pakettransport überschreitet die zulässige Strukturtiefe.")
        if "$ref" in node:
            ref = node["$ref"]
            if not ref.startswith("#/$defs/") or "/" in ref[len("#/$defs/"):]:
                raise ValueError("Unbekannte Paket-Schemareferenz.")
            target = self.canonical_schema.get("$defs", {}).get(ref[len("#/$defs/"):])
            if not isinstance(target, dict):
                raise ValueError("Unbekannte Paket-Schemareferenz.")
            return self._walk(target, value, encoding=encoding, depth=depth + 1)
        if "anyOf" in node:
            results = []
            for branch in node["anyOf"]:
                try:
                    result = self._walk(branch, value, encoding=encoding, depth=depth + 1)
                except ValueError:
                    continue
                if not any(_same(result, previous) for previous in results):
                    results.append(result)
            if len(results) != 1:
                raise ValueError("Pakettransport hat keinen eindeutigen Schemavertrag.")
            return results[0]
        if "oneOf" in node or "allOf" in node:
            raise ValueError("Nicht unterstützte Paket-Schemaform.")
        expected = node.get("type")
        fixed_size = _fixed_array_size(node)
        if fixed_size is not None:
            keys = ["v" + str(index) for index in range(fixed_size)]
            if encoding:
                if not isinstance(value, list) or len(value) != fixed_size:
                    raise ValueError("Paketliste hat nicht die festgelegte Anzahl Einträge.")
                return {key: self._walk(node["items"], item, encoding=True, depth=depth + 1)
                        for key, item in zip(keys, value, strict=True)}
            if not isinstance(value, dict) or set(value) != set(keys):
                raise ValueError("Feste Paketliste hat fehlende oder unerlaubte Einträge.")
            return [self._walk(node["items"], value[key], encoding=False, depth=depth + 1) for key in keys]
        valid = {"object": isinstance(value, dict), "array": isinstance(value, list),
                 "string": isinstance(value, str), "integer": type(value) is int,
                 "number": type(value) is int or (type(value) is float and math.isfinite(value)),
                 "boolean": type(value) is bool, "null": value is None}
        if expected in valid and not valid[expected]:
            raise ValueError("Ungültiger Pakettransport-Werttyp.")
        if "const" in node and not _same(value, node["const"]):
            raise ValueError("Pakettransport widerspricht einer Schemakonstante.")
        if "enum" in node and not any(_enum_same(value, item) for item in node["enum"]):
            raise ValueError("Pakettransport verwendet keinen erlaubten Schemawert.")
        if expected == "object" or "properties" in node:
            if not isinstance(value, dict):
                raise ValueError("Pakettransport erwartet ein Objekt.")
            props, result = node.get("properties", {}), {}
            incoming = {name if encoding else self.aliases[name]: name for name in props}
            if any(key not in incoming for key in value):
                raise ValueError("Unbekanntes Feld im Pakettransport.")
            for name, child in props.items():
                key = name if encoding else self.aliases[name]
                if name in self.constants:
                    constant = self.constants[name]
                    if encoding:
                        if key in value and not _same(value[key], constant):
                            raise ValueError("Pakettransport widerspricht einer gebundenen Konstante.")
                        if key not in value and name in node.get("required", []):
                            raise ValueError("Pflichtfeld fehlt im kanonischen Paket.")
                    elif key in value:
                        raise ValueError("Ausgelassene Schemakonstante wurde unerlaubt mitgesendet.")
                    else:
                        result[name] = copy.deepcopy(constant)
                    continue
                if key not in value:
                    if name in node.get("required", []):
                        raise ValueError("Pflichtfeld fehlt im Pakettransport.")
                    continue
                result[self.aliases[name] if encoding else name] = self._walk(
                    child, value[key], encoding=encoding, depth=depth + 1)
            return result
        if expected == "array":
            return [self._walk(node.get("items", {}), item, encoding=encoding, depth=depth + 1) for item in value]
        # Canonical Pydantic/domain validators still enforce lengths, ranges,
        # patterns, source fidelity, choice indexes and every graphic relation.
        return copy.deepcopy(value)


def bind(schema):
    """Bind aliases/constants to the FINAL request schema, never caller data."""
    _json(schema)  # Also rejects Python cycles/non-finite schema values.
    original = copy.deepcopy(schema)
    nodes = list(_nodes(original))
    unsupported = {"oneOf", "allOf", "if", "then", "else", "dependentRequired", "dependentSchemas",
                   "patternProperties", "propertyNames", "$dynamicRef", "unevaluatedProperties"}
    definitions = original.get("$defs", {})
    def refs(node):
        result = set()
        for item in _nodes(node):
            if unsupported.intersection(item):
                raise ValueError("Nicht unterstützte Paket-Schemaform.")
            if "$ref" not in item:
                continue
            value = item["$ref"]
            if not isinstance(value, str) or not value.startswith("#/$defs/") or value[len("#/$defs/"):] not in definitions:
                raise ValueError("Unbekannte Paket-Schemareferenz.")
            result.add(value[len("#/$defs/"):])
        return result
    refs(original)
    edges = {name: refs(node) for name, node in definitions.items()}
    visited = set()
    def acyclic(name, active):
        if name in active:
            raise ValueError("Zyklische Paket-Schemareferenz.")
        if name not in visited:
            for child in edges[name]:
                acyclic(child, active | {name})
            visited.add(name)
    for name in edges:
        acyclic(name, set())
    occurrences = {}
    for node in nodes:
        for name, child in node.get("properties", {}).items():
            occurrences.setdefault(name, []).append(_literal(child))
    aliases = {name: _alias(index) for index, name in enumerate(sorted(occurrences))}
    constants = {name: copy.deepcopy(values[0]) for name, values in occurrences.items()
                 if name not in _KEEP and values[0] is not _MISSING
                 and all(item is not _MISSING and _same(item, values[0]) for item in values)}
    # An optional omitted null cannot be distinguished from an absent optional
    # field. Only fields required in EVERY occurrence may be reconstructed.
    for node in nodes:
        for name in node.get("properties", {}):
            if name not in node.get("required", []):
                constants.pop(name, None)

    def project(node):
        if not isinstance(node, dict):
            return copy.deepcopy(node)
        fixed_size = _fixed_array_size(node)
        if fixed_size is not None:
            keys = ["v" + str(index) for index in range(fixed_size)]
            return {"type": "object", "properties": {key: project(node["items"]) for key in keys},
                    "required": keys, "additionalProperties": False,
                    "description": "Exact-length list: write v0, v1, etc. in their original order."}
        result = copy.deepcopy(node)
        if "properties" in node:
            result["properties"] = {aliases[name]: project(child) for name, child in node["properties"].items()
                                    if name not in constants}
            if "required" in node:
                result["required"] = [aliases[name] for name in node["required"] if name not in constants]
        for key in ("$defs", "definitions"):
            if key in node:
                result[key] = {name: project(child) for name, child in node[key].items()}
        for key in ("items", "additionalProperties"):
            if isinstance(node.get(key), dict):
                result[key] = project(node[key])
        for key in ("anyOf", "oneOf", "allOf"):
            if key in node:
                result[key] = [project(child) for child in node[key]]
        return result

    return Binding(original, project(original), aliases, constants)
