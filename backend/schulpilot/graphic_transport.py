"""Request-bound native Graphic spelling; canonical validation remains final.

Only our proven coherent Graphic union and its finite fraction-pair enum are
projected. No answers, literal quotes, source references or disclosure change.
"""
import copy
import json
import math
from dataclasses import dataclass

from .graphic_schema import bind_coherent_graphics

REVISION = "native-graphic-1"
_ERROR = "Grafiktransport entspricht nicht dem gebundenen Anfrageformat."


def _pair_key(value):
    if (not isinstance(value, list) or len(value) != 2
        or any(type(item) not in (int, float) or not math.isfinite(item) or item != int(item) for item in value)):
        raise ValueError(_ERROR)
    return json.dumps([int(item) for item in value], separators=(",", ":"))


def _presentations(value, transform):
    """Visit response presentations only; answer/source strings are opaque."""
    if isinstance(value, list):
        for child in value:
            _presentations(child, transform)
    elif isinstance(value, dict):
        for name, child in value.items():
            if name == "presentation" and isinstance(child, dict):
                blocks = child.get("blocks")
                if isinstance(blocks, list):
                    for block in blocks:
                        if isinstance(block, dict) and block.get("kind") == "fraction":
                            transform(block)
            _presentations(child, transform)


@dataclass(frozen=True)
class Binding:
    canonical_schema: dict
    wire_schema: dict
    pairs: dict

    @property
    def rules(self):
        return ("\n" + REVISION + ": Nur bei Graphic.kind=fraction wird numbers auf dem Transport als "
                "EXAKTER String aus dem Schema-Enum ausgegeben, z.B. \"[1,4]\" statt des Arrays [1,4]. "
                "Der Server liest daraus unverändert das gebundene Zahlenpaar [n,d]. Keine anderen Felder, "
                "Antworten, Originalzitate, Quellenbezüge oder Offenlegungsstufen ändern. Alle Grafikregeln gelten weiter.")

    def encode(self, canonical):
        """Strict encoder for synthetic wire fixtures, never response repair."""
        json.dumps(canonical, allow_nan=False)
        result = copy.deepcopy(canonical)

        def encode_block(block):
            key = _pair_key(block.get("numbers"))
            if key not in self.pairs:
                raise ValueError(_ERROR)
            block["numbers"] = key

        _presentations(result, encode_block)
        return result

    def decode(self, wire):
        json.dumps(wire, allow_nan=False)
        result = copy.deepcopy(wire)

        def decode_block(block):
            key = block.get("numbers")
            if type(key) is not str or key not in self.pairs:
                raise ValueError(_ERROR)
            block["numbers"] = copy.deepcopy(self.pairs[key])

        _presentations(result, decode_block)
        return result


def bind(schema):
    """Project only the exact known binder output after all Unit schema hooks.

    The reconstruction proves that each union branch already contains EVERY
    base constraint. Arbitrary anyOf/object siblings must never be discarded.
    The canonical copy stays intact for introspection and final validators.
    """
    graphic = schema.get("$defs", {}).get("Graphic")
    if not graphic or "anyOf" not in graphic:
        return None
    original = copy.deepcopy(schema)
    proof = {"$defs": {"Graphic": copy.deepcopy(graphic)}}
    proof["$defs"]["Graphic"].pop("anyOf")
    bind_coherent_graphics(proof)
    if proof["$defs"]["Graphic"] != graphic:
        raise ValueError(_ERROR)
    branches = copy.deepcopy(graphic["anyOf"])
    pairs = {}
    for branch in branches:
        props = branch["properties"]
        if (branch.get("type") != "object" or branch.get("additionalProperties") is not False
            or set(branch.get("required", [])) != set(props)):
            raise ValueError(_ERROR)
        if "fraction" in props["kind"]["enum"]:
            if props["kind"]["enum"] != ["fraction"]:
                raise ValueError(_ERROR)
            values = props["numbers"]["enum"]
            pairs = {_pair_key(value): copy.deepcopy(value) for value in values}
            if len(pairs) != len(values):
                raise ValueError(_ERROR)
            props["numbers"] = {"type": "string", "enum": list(pairs)}
    wire = copy.deepcopy(original)
    wire["$defs"]["Graphic"] = {"anyOf": branches}
    return Binding(original, wire, pairs)
