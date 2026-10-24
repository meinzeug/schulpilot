"""Separate image transport bytes from the operator's image risk allowance.

An allowance is an explicit, versioned operator estimate for one exact route.
It is NOT a documented model tokenizer formula or a guaranteed invoice ceiling.
No allowance means the previous conservative encoded-byte treatment remains.
Reservations, actual receipts and the over-reservation emergency stop remain.
"""

import hashlib
import io
import json
import warnings

from PIL import Image


def projection(config, function, text_bytes, image_bytes, encoded_image_bytes):
    image_tokens, basis, profile_hash = encoded_image_bytes, "encoded_bytes", None
    if image_bytes and function == "extract" and config.provider == "openrouter":
        from .model_routing import selection

        route = selection(config)
        profile = route.get("route", {}).get("vision_budget")
        if (profile and profile["model"] == config.model
                and profile["upstreams"] == route.get("route", {}).get("upstreams")):
            # selection is tied to the exact, evaluated and reserved model. No
            # wildcard model family or automatic allowance for another route.
            try:
                with warnings.catch_warnings():
                    warnings.simplefilter("error", Image.DecompressionBombWarning)
                    with Image.open(io.BytesIO(image_bytes)) as image:
                        width, height = image.size
                        allowed = (0 < width <= profile["max_side"] and 0 < height <= profile["max_side"]
                                   and width * height <= profile["max_pixels"])
            except (OSError, ValueError, Image.DecompressionBombError, Image.DecompressionBombWarning):
                allowed = False
            if allowed:
                image_tokens, basis = profile["image_tokens"], "operator_image_estimate"
                profile_hash = hashlib.sha256(json.dumps(profile, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
    # A byte per text token plus framing remains deliberately conservative.
    input_bound = text_bytes + image_tokens + 4096
    projected = (input_bound * config.input_per_million_micros
                 + config.max_output_tokens * config.output_per_million_micros + 999_999) // 1_000_000
    return {"version": 1, "basis": basis if image_bytes else "text_bytes",
            "text_bytes": text_bytes, "image_input_allowance": image_tokens,
            "profile_sha256": profile_hash, "projected_micros": projected,
            "reserved_micros": config.reserve_micros, "guaranteed_invoice_ceiling": False}
