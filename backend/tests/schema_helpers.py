"""Read actual schema contracts independently of private $defs anchor names."""
import copy


def resolved(schema, node=None):
    value = schema if node is None else node
    if isinstance(value, dict):
        if "$ref" in value:
            assert set(value) == {"$ref"}
            return resolved(schema, schema["$defs"][value["$ref"].rsplit("/", 1)[-1]])
        return {key: resolved(schema, child) for key, child in value.items() if key != "$defs"}
    if isinstance(value, list):
        return [resolved(schema, child) for child in value]
    return copy.deepcopy(value)


def package_questions(schema, group=0):
    unit = resolved(schema)["properties"]["units"]["items"]
    if "anyOf" in unit:
        unit = unit["anyOf"][group]
    return unit["properties"]["questions"]["items"]["anyOf"]


def object_with(schema, required):
    def walk(node):
        if isinstance(node, dict):
            if required <= node.get("properties", {}).keys():
                yield node
            for child in node.values():
                yield from walk(child)
        elif isinstance(node, list):
            for child in node:
                yield from walk(child)
    return next(walk(resolved(schema)))
