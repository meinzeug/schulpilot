"""Synthetic starvation regressions: no network, media or provider calls."""
import asyncio
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from contextlib import suppress

import httpx
import pytest
from fastapi import Depends
from schulpilot import family_calls, main
from schulpilot.db import DB, engine, get_db
from sqlalchemy import create_engine, text
from sqlalchemy.exc import TimeoutError as PoolTimeout
from sqlalchemy.pool import QueuePool
from starlette.concurrency import run_in_threadpool


@pytest.mark.parametrize("parallel_probes", [1, 8])
def test_full_pool_keeps_loop_health_and_dependency_cleanup_responsive(parallel_probes):
    # Only this test engine is constrained. Production pool/timeouts stay intact.
    small = create_engine(engine.url, poolclass=QueuePool, pool_size=1,
        max_overflow=0, pool_timeout=0.4,
        connect_args={"check_same_thread": False} if engine.dialect.name == "sqlite" else {})
    DB.configure(bind=small)
    routes_before = set(id(route) for route in main.app.router.routes)

    async def scenario():
        entered, release = asyncio.Event(), asyncio.Event()
        ticks = []

        async def held_session(db=Depends(get_db)):
            await run_in_threadpool(db.execute, text("SELECT 1"))
            entered.set()
            await release.wait()
            return {"released": True}

        async def probe():
            return {"gate_passed": True}

        # Temporary test-only routes exercise the real global gate/get_db path.
        main.app.add_api_route("/api/_pool_test/held", held_session, methods=["GET"])
        main.app.add_api_route("/api/_pool_test/probe", probe, methods=["GET"])

        async def ticker():
            while True:
                ticks.append(time.monotonic())
                await asyncio.sleep(0.01)

        async with httpx.AsyncClient(transport=httpx.ASGITransport(app=main.app),
                base_url="http://testserver") as client:
            held = asyncio.create_task(client.get("/api/_pool_test/held"))
            pending = []
            pulse = None
            try:
                await asyncio.wait_for(entered.wait(), 2)
                pulse = asyncio.create_task(ticker())
                await asyncio.sleep(0.02)
                pending = [asyncio.create_task(client.get("/api/_pool_test/probe"))
                    for _ in range(parallel_probes)]
                pending.append(asyncio.create_task(client.get("/api/health")))
                # This release and the dependency generator's __exit__ both
                # need a responsive event loop while pool checkout is waiting.
                await asyncio.sleep(0.08)
                release.set()
                responses = await asyncio.wait_for(asyncio.gather(held, *pending), 3)
                assert all(response.status_code == 200 for response in responses)
                assert responses[0].json() == {"released": True}
                assert responses[-1].json()["status"] == "ok"
                assert len(ticks) >= 5
                assert max(b - a for a, b in zip(ticks, ticks[1:])) < 0.25
                assert small.pool.checkedout() == 0
            finally:
                release.set()
                if pulse:
                    pulse.cancel()
                    with suppress(asyncio.CancelledError):
                        await pulse
                await asyncio.gather(held, *pending, return_exceptions=True)

    try:
        asyncio.run(scenario())
    finally:
        main.app.router.routes[:] = [route for route in main.app.router.routes if id(route) in routes_before]
        DB.configure(bind=engine)
        small.dispose()


@pytest.mark.parametrize("required", [False, True])
def test_setup_gate_session_lifecycle_stays_on_one_worker(monkeypatch, required):
    events = []

    class GateSession:
        def __enter__(self):
            events.append(("open", threading.get_ident()))
            return self

        def __exit__(self, *_):
            events.append(("close", threading.get_ident()))

    def check(db):
        assert isinstance(db, GateSession)
        events.append(("query", threading.get_ident()))
        return required

    monkeypatch.setattr(main, "DB", GateSession)
    monkeypatch.setattr(main.installation, "required", check)

    async def scenario():
        loop_thread = threading.get_ident()
        async with httpx.AsyncClient(transport=httpx.ASGITransport(app=main.app),
                base_url="http://testserver") as client:
            response = await client.get("/api/_missing_test_route")
        assert response.status_code == (503 if required else 404)
        if required:
            assert response.json()["setup_required"] is True
        assert [event for event, _ in events] == ["open", "query", "close"]
        assert len({thread for _, thread in events}) == 1
        assert events[0][1] != loop_thread

    asyncio.run(scenario())


def test_setup_gate_pool_failure_closes_session_and_redacts_errors(monkeypatch, caplog):
    closed = []

    class GateSession:
        def __enter__(self):
            return self

        def __exit__(self, *_):
            closed.append(True)

    def failed(_):
        raise PoolTimeout("SYNTHETIC-PRIVATE-DATABASE-DETAIL")

    monkeypatch.setattr(main, "DB", GateSession)
    monkeypatch.setattr(main.installation, "required", failed)

    async def scenario():
        async with httpx.AsyncClient(transport=httpx.ASGITransport(app=main.app),
                base_url="http://testserver") as client:
            return await client.get("/api/_missing_test_route")

    response = asyncio.run(scenario())
    assert response.status_code == 500 and closed == [True]
    assert "SYNTHETIC-PRIVATE-DATABASE-DETAIL" not in response.text + caplog.text
    assert "request_failed method=GET type=TimeoutError" in caplog.text


def test_signal_expiry_skips_busy_lock_then_prunes_without_waiting():
    memory = family_calls.SignalMemory()
    payload = family_calls.Signal(idempotency_key="busy-lock-offer", kind="offer", payload={"sdp": "v=0\r\nSYNTHETIC"})
    memory.put("synthetic-call", "child", "parent", payload, 100)
    entered, release = threading.Event(), threading.Event()

    def holder():
        with memory.lock:
            entered.set()
            release.wait(timeout=0.5)

    with ThreadPoolExecutor(max_workers=1) as pool:
        future = pool.submit(holder)
        assert entered.wait(timeout=1)
        try:
            started = time.monotonic()
            assert memory.expire(191) is False
            assert time.monotonic() - started < 0.1
        finally:
            release.set()
        future.result(timeout=1)
    assert memory.expire(191) is True
    assert memory.calls["synthetic-call"]["items"] == []
    assert memory.calls["synthetic-call"]["seq"] == 1
