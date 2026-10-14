from schulpilot.config import settings


def test_privacy_is_readable_without_javascript_or_login(api):
    object.__setattr__(settings, "operator_name", "Synthetic <script>unsafe</script>")
    response = api.get("/api/legal/privacy")
    assert response.status_code == 200
    assert response.headers["content-type"].startswith("text/html")
    assert "<script>" not in response.text
    assert "Synthetic &lt;script&gt;unsafe&lt;/script&gt;" in response.text
    for content in ["Google", "openid", "email", "Firebase", "OpenRouter", "365 Tage", "Konto löschen"]:
        assert content in response.text
    assert "client_secret" not in response.text
    assert "sp_session" not in response.text
