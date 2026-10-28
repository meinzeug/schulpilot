"""Fixed PayPal Orders v2 transport. No raw response/credential logging or retry."""

import json
import re
from dataclasses import dataclass, field
from decimal import Decimal, InvalidOperation
from time import monotonic

import httpx

BASES = {"sandbox": "https://api-m.sandbox.paypal.com", "live": "https://api-m.paypal.com"}
IDENTIFIER = re.compile(r"^[A-Za-z0-9_-]{1,160}$")
MAX_RESPONSE = 65536


@dataclass(frozen=True)
class Connection:
    environment: str
    client_id: str
    client_secret: str = field(repr=False)
    merchant_id: str = ""
    revision: int = 0


class PayPalError(Exception):
    """Only fixed neutral codes leave the adapter."""

    def __init__(self, code="provider_unavailable", *, uncertain=True):
        self.code, self.uncertain = code, uncertain
        super().__init__(code)


def money(cents):
    if type(cents) is not int or cents <= 0:
        raise PayPalError("invalid_amount", uncertain=False)
    return f"{cents // 100}.{cents % 100:02d}"


def cents(value):
    if not isinstance(value, str) or not re.fullmatch(r"[0-9]{1,8}\.[0-9]{2}", value):
        raise PayPalError("invalid_amount")
    try:
        result = Decimal(value) * 100
    except InvalidOperation:
        raise PayPalError("invalid_amount") from None
    return int(result)


def identifier(value, *, limit=64):
    if not isinstance(value, str) or len(value) > limit or not IDENTIFIER.fullmatch(value):
        raise PayPalError("invalid_response")
    return value


def client():
    return httpx.Client(timeout=httpx.Timeout(5, connect=5), follow_redirects=False)


def _json(response, deadline):
    content = bytearray()
    for chunk in response.iter_bytes():
        if monotonic() >= deadline:
            raise PayPalError("provider_unavailable")
        if len(content) + len(chunk) > MAX_RESPONSE:
            raise PayPalError("invalid_response")
        content.extend(chunk)
    try:
        value = json.loads(content)
    except (ValueError, UnicodeError):
        raise PayPalError("invalid_response") from None
    if not isinstance(value, dict):
        raise PayPalError("invalid_response")
    return value


def request(connection, method, path, *, payload=None, request_id=None):
    base = BASES.get(connection.environment)
    if base is None or not path.startswith(
        (
            "/v2/checkout/orders",
            "/v2/payments/captures/",
            "/v2/payments/refunds/",
            "/v1/notifications/verify-webhook-signature",
        )
    ):
        raise PayPalError("invalid_request", uncertain=False)
    deadline = monotonic() + 20
    try:
        with client() as transport:
            with transport.stream(
                "POST",
                base + "/v1/oauth2/token",
                auth=(connection.client_id, connection.client_secret),
                data={"grant_type": "client_credentials"},
                headers={"Accept": "application/json"},
            ) as token_reply:
                if token_reply.status_code != 200:
                    raise PayPalError("credentials_unavailable", uncertain=False)
                token = _json(token_reply, deadline).get("access_token")
            if not isinstance(token, str) or not token or len(token) > 16384:
                raise PayPalError("credentials_unavailable", uncertain=False)
            headers = {
                "Authorization": "Bearer " + token,
                "Accept": "application/json",
                "Prefer": "return=representation",
            }
            if request_id:
                headers["PayPal-Request-Id"] = request_id
            if monotonic() >= deadline:
                raise PayPalError("provider_unavailable", uncertain=False)
            with transport.stream(method, base + path, headers=headers, json=payload) as response:
                if response.status_code not in (200, 201, 202):
                    # Even 422 can mean ORDER_ALREADY_CAPTURED or duplicate
                    # invoice, not a proven declined payment. Only canonical
                    # resource state can resolve a persisted mutation intent.
                    raise PayPalError("provider_unavailable")
                return _json(response, deadline)
    except (httpx.HTTPError, OSError):
        raise PayPalError() from None


def create_order(connection, order, request_id):
    return request(
        connection,
        "POST",
        "/v2/checkout/orders",
        request_id=request_id,
        payload={
            "intent": "CAPTURE",
            "payment_source": (
                {"google_pay": {"attributes": {"verification": {"method": "SCA_WHEN_REQUIRED"}}}}
                if order.payment_method == "google_pay"
                else {
                    "paypal": {"experience_context": {"shipping_preference": "NO_SHIPPING", "user_action": "PAY_NOW"}}
                }
            ),
            "purchase_units": [
                {
                    "reference_id": order.id,
                    "custom_id": order.id,
                    "invoice_id": order.payment_reference,
                    "payee": {"merchant_id": connection.merchant_id},
                    "amount": {"currency_code": order.currency, "value": money(order.amount_cents)},
                    "description": "SchuleSchlau · " + order.offer["name"] + " · 30 Tage",
                }
            ],
        },
    )


def capture_order(connection, provider_order_id, request_id):
    return request(
        connection,
        "POST",
        "/v2/checkout/orders/" + identifier(provider_order_id) + "/capture",
        payload={},
        request_id=request_id,
    )


def read_order(connection, provider_order_id):
    return request(connection, "GET", "/v2/checkout/orders/" + identifier(provider_order_id))


def read_capture(connection, capture_id):
    return request(connection, "GET", "/v2/payments/captures/" + identifier(capture_id))


def read_refund(connection, refund_id):
    return request(connection, "GET", "/v2/payments/refunds/" + identifier(refund_id))


def verify_webhook(connection, headers, event, webhook_id):
    mapping = {
        "auth_algo": "paypal-auth-algo",
        "cert_url": "paypal-cert-url",
        "transmission_id": "paypal-transmission-id",
        "transmission_sig": "paypal-transmission-sig",
        "transmission_time": "paypal-transmission-time",
    }
    values = {key: headers.get(name, "") for key, name in mapping.items()}
    if any(not isinstance(value, str) or not value or len(value) > 1000 for value in values.values()):
        return False
    # Never download an attacker-selected certificate URL locally.
    try:
        certificate = httpx.URL(values["cert_url"])
    except httpx.InvalidURL:
        return False
    if (
        certificate.scheme != "https"
        or certificate.host
        not in ("api.paypal.com", "api-m.paypal.com", "api.sandbox.paypal.com", "api-m.sandbox.paypal.com")
        or not certificate.path.startswith("/v1/notifications/certs/")
        or certificate.query
        or certificate.fragment
        or certificate.username
        or certificate.password
        or certificate.port not in (None, 443)
    ):
        return False
    live_host = "sandbox" not in certificate.host
    if live_host != (connection.environment == "live"):
        return False
    verified = request(
        connection,
        "POST",
        "/v1/notifications/verify-webhook-signature",
        payload={**values, "webhook_id": webhook_id, "webhook_event": event},
    )
    return verified.get("verification_status") == "SUCCESS"
