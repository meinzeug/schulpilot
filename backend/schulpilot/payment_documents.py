"""Authenticated, isolated checkout documents; no provider work on GET."""

import re
import secrets
from html import escape
from pathlib import Path

from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import HTMLResponse, RedirectResponse, Response

from .commerce import owned_order
from .config import settings
from .db import Family, get_db
from .security import admin, authenticated, parent

router = APIRouter(tags=["Vertragsoberflächen"])


def template(name):
    # Only fixed callers choose a name, never request paths or user content.
    directory = Path(settings.web_dir) if settings.web_dir else Path(__file__).resolve().parents[2] / "app" / "web"
    path = directory / name
    if not path.is_file() or path.stat().st_size > 65536:
        raise HTTPException(503, "Die Oberfläche wird gerade vorbereitet. Bitte später erneut öffnen.")
    return path.read_text(encoding="utf-8")


def document(name, *, fields=None, payment=False):
    nonce = secrets.token_urlsafe(24)
    text = template(name).replace("__CSP_NONCE__", escape(nonce, quote=True))
    for key, value in (fields or {}).items():
        text = text.replace(key, escape(str(value or ""), quote=True))
    if payment:
        policy = (
            "default-src 'none'; "
            f"script-src 'self' 'nonce-{nonce}' https://*.paypal.com https://*.paypalobjects.com https://pay.google.com; "
            "style-src 'self' 'unsafe-inline'; img-src 'self' data: https://*.paypal.com https://*.paypalobjects.com https://www.gstatic.com; "
            "connect-src 'self' https://*.paypal.com https://pay.google.com https://www.google.com https://accounts.google.com https://account.google.com; "
            "frame-src https://*.paypal.com https://pay.google.com; "
            "form-action 'self' https://*.paypal.com https://pay.google.com; "
            "font-src 'self'; base-uri 'none'; object-src 'none'; frame-ancestors 'none'"
        )
    else:
        policy = (
            f"default-src 'none'; script-src 'self' 'nonce-{nonce}'; style-src 'self'; "
            "img-src 'self' data:; connect-src 'self'; font-src 'self'; "
            "form-action 'self'; base-uri 'none'; object-src 'none'; frame-ancestors 'none'"
        )
    return HTMLResponse(text, headers={
        "Content-Security-Policy": policy,
        "Cache-Control": "no-store",
        "Referrer-Policy": "no-referrer",
        "X-Frame-Options": "DENY",
        "X-Content-Type-Options": "nosniff",
    })


def web_request(request):
    # The normal web cookie is deliberately /api scoped. Never broaden it for
    # checkout and never copy native bearer tokens into document links.
    if not request.cookies.get("sp_session") or request.headers.get("authorization"):
        raise HTTPException(401, "Bitte im Web-Elternkonto anmelden und die Bestellung dort öffnen.")


def document_access(request, db, check_role):
    try:
        web_request(request)
        return check_role(authenticated(request, db))
    except HTTPException as error:
        if error.status_code == 401:
            return RedirectResponse("/login", status_code=303)
        if error.status_code != 403:
            raise
        return HTMLResponse(
            '<!doctype html><html lang="de"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">'
            '<title>Zugang prüfen · SCHULPILOT</title><h1>Bitte den passenden Zugang verwenden</h1>'
            '<p>Diese Vertragsseite gehört zum berechtigten Eltern- beziehungsweise Betreiberkonto.</p><a href="/app">Zur Übersicht</a></html>',
            status_code=403, headers={"Cache-Control": "no-store", "Content-Security-Policy": "default-src 'none'; frame-ancestors 'none'; base-uri 'none'"},
        )


def private_order(db, p, identifier):
    if not re.fullmatch(r"[a-f0-9]{32}", identifier):
        raise HTTPException(404, "Bestellung nicht gefunden.")
    row = owned_order(db, p, identifier)
    family = db.get(Family, row.family_id)
    if not family or family.synthetic:
        raise HTTPException(403, "Diese Vertragsfunktion ist nur im eigenen regulären Elternkonto verfügbar.")
    return row


@router.get("/orders/{order_id}/payment-checkout", response_class=HTMLResponse)
def checkout(order_id: str, request: Request, db=Depends(get_db)):
    p = document_access(request, db, parent)
    if isinstance(p, Response):
        return p
    row = private_order(db, p, order_id)
    if row.payment_method not in ("paypal", "google_pay"):
        return RedirectResponse("/bestellungen", status_code=303)
    return document("payment_checkout.html", fields={"__ORDER_ID__": row.id}, payment=True)


@router.get("/orders/{order_id}/withdrawal-form", response_class=HTMLResponse)
def withdrawal_form(order_id: str, request: Request, db=Depends(get_db)):
    p = document_access(request, db, parent)
    if isinstance(p, Response):
        return p
    row = private_order(db, p, order_id)
    return document("withdrawal.html", fields={
        "__WITHDRAWAL_MODE__": "owner", "__ORDER_ID__": row.id,
        "__BUYER_NAME__": p.user.display_name, "__CONTACT_EMAIL__": p.user.email,
        "__ORDER_REFERENCE__": row.payment_reference,
    })


@router.get("/legal/withdrawal", response_class=HTMLResponse)
def public_withdrawal_form():
    return document("withdrawal.html", fields={
        "__WITHDRAWAL_MODE__": "public", "__ORDER_ID__": "",
        "__BUYER_NAME__": "", "__CONTACT_EMAIL__": "", "__ORDER_REFERENCE__": "",
    })


@router.get("/admin/withdrawals/dashboard", response_class=HTMLResponse)
def withdrawal_dashboard(request: Request, db=Depends(get_db)):
    p = document_access(request, db, admin)
    if isinstance(p, Response):
        return p
    return document("withdrawal_admin.html")
