"""Lossless, shallow graphic transport for native structured outputs.

Canonical explanations, sources and disclosure remain unchanged. Only graphic
objects move to a request-local table; the ordinary validators run after decode.
"""
import copy
import re
from dataclasses import dataclass

REVISION = "graphic-table-1"
TABLE = "graphic_catalog"
ERROR = "Der Grafiktransport entspricht nicht dem angeforderten Grafikformat."
MAX_GRAPHICS = 256


def nesting_depth(schema):
    """Count actual JSON containers, including arrays and referenced objects."""
    def depth(node, active=()):
        if not isinstance(node, dict):
            return 0
        if "$ref" in node:
            ref = node["$ref"]
            if not ref.startswith("#/$defs/") or ref in active:
                raise ValueError(ERROR)
            return depth(schema["$defs"][ref.removeprefix("#/$defs/")], (*active, ref))
        branches = [depth(branch, active) for branch in node.get("anyOf", [])]
        children = [depth(child, active) for child in node.get("properties", {}).values()]
        if isinstance(node.get("items"), dict):
            children.append(depth(node["items"], active))
        own = int(node.get("type") in ("object", "array"))
        return max([*branches, own + max([0, *children])])
    return depth(schema)


def _graphics(value, visit):
    if isinstance(value, list):
        for child in value:
            _graphics(child, visit)
    elif isinstance(value, dict):
        presentation = value.get("presentation")
        if isinstance(presentation, dict) and isinstance(presentation.get("blocks"), list):
            presentation["blocks"] = [visit(block) for block in presentation["blocks"]]
        for child in value.values():
            _graphics(child, visit)


@dataclass(frozen=True)
class Binding:
    canonical_schema: dict
    wire_schema: dict

    @property
    def rules(self):
        return ("\n" + REVISION + ": Grafikblöcke werden vollständig in der obersten Liste "
                "graphic_catalog ausgegeben: je Eintrag {id: g0, graphic: vollständiger Grafikblock}. "
                "presentation.blocks enthält ausschließlich passende Eintrags-IDs als Strings. "
                "Jede ID genau einmal definieren und genau einmal verwenden; keine unbenutzten Einträge. "
                "Ohne Grafik graphic_catalog=[]. Sämtliche Grafik-, Objekt-, Phasen-, Quellen- und Aufdeckregeln bleiben unverändert. "
                "Der Server setzt jeden Block verlustfrei an dieselbe Stelle zurück.")

    def encode(self, canonical):
        if not isinstance(canonical, dict) or TABLE in canonical:
            raise ValueError(ERROR)
        result = copy.deepcopy(canonical)
        catalog = []
        def encode_block(block):
            if not isinstance(block, dict) or len(catalog) >= MAX_GRAPHICS:
                raise ValueError(ERROR)
            key = "g" + str(len(catalog))
            catalog.append({"id": key, "graphic": block})
            return key
        _graphics(result, encode_block)
        result[TABLE] = catalog
        return result

    def decode(self, wire):
        if not isinstance(wire, dict):
            raise ValueError(ERROR)
        result = copy.deepcopy(wire)
        catalog = result.pop(TABLE, [])
        if not isinstance(catalog, list) or len(catalog) > MAX_GRAPHICS:
            raise ValueError(ERROR)
        graphics = {}
        for row in catalog:
            if (not isinstance(row, dict) or set(row) != {"id", "graphic"}
                    or not isinstance(row["id"], str) or not re.fullmatch(r"g[0-9]{1,3}", row["id"])
                    or row["id"] in graphics or not isinstance(row["graphic"], dict)):
                raise ValueError(ERROR)
            graphics[row["id"]] = row["graphic"]
        used = set()
        def decode_block(block):
            key = block
            if not isinstance(key, str) or key not in graphics or key in used:
                raise ValueError(ERROR)
            used.add(key)
            return copy.deepcopy(graphics[key])
        _graphics(result, decode_block)
        if used != set(graphics):
            raise ValueError(ERROR)
        return result


def bind(schema):
    if nesting_depth(schema) <= 10:
        return None
    original = copy.deepcopy(schema)
    wire = copy.deepcopy(schema)
    ref = "#/$defs/Graphic"
    graphic = copy.deepcopy(wire.get("$defs", {}).get("Graphic"))
    if not isinstance(graphic, dict):
        return None
    replaced = 0
    def rewrite(node):
        nonlocal replaced
        if isinstance(node, list):
            for child in node:
                rewrite(child)
        elif isinstance(node, dict):
            if node.get("$ref") == ref:
                if set(node) != {"$ref"}:
                    raise ValueError(ERROR)
                node.clear()
                node.update(type="string", pattern=r"^g[0-9]{1,3}$")
                replaced += 1
            else:
                for child in node.values():
                    rewrite(child)
    rewrite(wire)
    if not replaced or TABLE in wire["properties"]:
        raise ValueError(ERROR)
    wire["properties"][TABLE] = {"type": "array", "minItems": 0, "maxItems": MAX_GRAPHICS,
        "items": {"type": "object", "additionalProperties": False, "required": ["id", "graphic"],
            "properties": {"id": {"type": "string", "pattern": r"^g[0-9]{1,3}$"},
                           "graphic": {"$ref": ref}}}}
    wire["required"] = [*wire["required"], TABLE]
    if nesting_depth(wire) > 10:
        raise ValueError(ERROR)
    return Binding(original, wire)
