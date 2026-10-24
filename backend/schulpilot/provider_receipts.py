"""Hashes and explicit transmitted parameters; never retain prompts or images."""
import hashlib
import json


def _hash(value):
    return hashlib.sha256(json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def request_receipt(provider, body, schema):
    if provider == "codex":
        prompt = [body.get("system"), body.get("payload")]
        detail = None
        reasoning = {"effort": body["reasoning_effort"]} if "reasoning_effort" in body else None
        upstreams = []
    elif provider == "openai":
        prompt = [body.get("instructions"), [part.get("text") for message in body.get("input", []) for part in message.get("content", []) if part.get("type") == "input_text"]]
        details = [part.get("detail") for message in body.get("input", []) for part in message.get("content", []) if part.get("type") == "input_image"]
        detail = details[0] if details else None
        reasoning = body.get("reasoning")
        upstreams = []
    else:
        prompt = [[message.get("role"), message.get("content") if isinstance(message.get("content"), str) else
                   [part.get("text") for part in message.get("content", []) if part.get("type") == "text"]]
                  for message in body.get("messages", [])]
        details = [part["image_url"].get("detail") for message in body.get("messages", [])
                   if isinstance(message.get("content"), list) for part in message["content"] if part.get("type") == "image_url"]
        detail = details[0] if details else None
        reasoning = body.get("reasoning")
        upstreams = body.get("provider", {}).get("only", [])
    return {"version": 1, "provider": provider, "model": body.get("model"),
            "schema_sha256": _hash(schema), "prompt_sha256": _hash(prompt),
            "image_detail": detail, "reasoning": reasoning,
            "max_output_tokens": body.get("max_tokens", body.get("max_output_tokens")),
            "upstreams": upstreams, "parameter_basis": "actual_transmitted_request"}
