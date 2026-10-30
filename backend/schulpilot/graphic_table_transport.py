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
CATALOG_ERROR = "Grafiktransport: ungültige Tabelle."
ROW_ERROR = "Grafiktransport: ungültiger Eintrag."
DUPLICATE_ERROR = "Grafiktransport: doppelte Kennung."
REFERENCE_ERROR = "Grafiktransport: unbekannter Verweis."
REUSED_ERROR = "Grafiktransport: mehrfach verwendeter Verweis."
UNUSED_ERROR = "Grafiktransport: nicht verwendeter Eintrag."
MAX_GRAPHICS = 256


def _prepared_ids(schema):
    """Only finite IDs already declared by a presentation's canonical schema."""
    ids = set()
    def walk(node):
        if isinstance(node, dict):
            props = node.get('properties', {})
            if {'blocks', 'version', 'evidence_kind'} <= props.keys():
                items = props['blocks'].get('items', {})
                if items.get('type') == 'string' and isinstance(items.get('enum'), list):
                    ids.update(item for item in items['enum'] if isinstance(item, str))
            for child in node.values():
                walk(child)
        elif isinstance(node, list):
            for child in node:
                walk(child)
    walk(schema)
    if any(re.fullmatch(r'g[0-9]{1,3}', item) for item in ids):
        raise ValueError(ERROR)
    return ids


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
                "Jede Tabellen-ID genau einmal definieren und genau einmal verwenden; keine unbenutzten Einträge. "
                "Ausnahme: Bereits als String-Enum gebundene vorbereitete Grafik-IDs bleiben unverändert direkt in blocks; "
                "sie gehören NICHT in graphic_catalog. Nur vollständige Graphic-Objekte werden ausgelagert. "
                "Ohne Grafik graphic_catalog=[]. Sämtliche Grafik-, Objekt-, Phasen-, Quellen- und Aufdeckregeln bleiben unverändert. "
                "Der Server setzt jeden Block verlustfrei an dieselbe Stelle zurück.")

    def encode(self, canonical):
        if not isinstance(canonical, dict) or TABLE in canonical:
            raise ValueError(ERROR)
        result = copy.deepcopy(canonical)
        catalog = []
        prepared = _prepared_ids(self.canonical_schema)
        def encode_block(block):
            if isinstance(block, str) and block in prepared:
                return block
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
            raise ValueError(CATALOG_ERROR)
        graphics = {}
        for row in catalog:
            if (not isinstance(row, dict) or set(row) != {"id", "graphic"}
                    or not isinstance(row["id"], str) or not re.fullmatch(r"g[0-9]{1,3}", row["id"])
                    or not isinstance(row["graphic"], dict)):
                raise ValueError(ROW_ERROR)
            if row["id"] in graphics:
                raise ValueError(DUPLICATE_ERROR)
            graphics[row["id"]] = row["graphic"]
        used = set()
        prepared = _prepared_ids(self.canonical_schema)
        def decode_block(block):
            key = block
            if isinstance(key, str) and key in prepared:
                return key
            if not isinstance(key, str) or key not in graphics:
                raise ValueError(REFERENCE_ERROR)
            if key in used:
                raise ValueError(REUSED_ERROR)
            used.add(key)
            return copy.deepcopy(graphics[key])
        _graphics(result, decode_block)
        if used != set(graphics):
            raise ValueError(UNUSED_ERROR)
        return result


def bind(schema):
    if nesting_depth(schema) <= 10:
        return None
    _prepared_ids(schema)  # Reject ambiguous namespaces before any dispatch.
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
