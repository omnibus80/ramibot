import asyncio
import pytest
from httpx import AsyncClient, ASGITransport
import main
from main import app


@pytest.fixture
def anyio_backend():
    return "asyncio"


@pytest.mark.anyio
async def test_health_endpoint():
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.get("/api/health")
    assert response.status_code == 200
    data = response.json()
    assert data == {"status": "ok"}


@pytest.mark.anyio
async def test_health_returns_json():
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.get("/api/health")
    assert response.headers["content-type"] == "application/json"


@pytest.mark.anyio
async def test_parallel_agents_caps_at_five_workers(monkeypatch):
    active = 0
    peak = 0

    class FakeAdapter:
        async def generate(self, _messages, _model, **_kwargs):
            nonlocal active, peak
            active += 1
            peak = max(peak, active)
            await asyncio.sleep(0.01)
            active -= 1
            return {"content": "done"}

    monkeypatch.setattr(main, "get_adapter", lambda _provider: FakeAdapter())
    monkeypatch.setattr(main, "load_settings", lambda: {})
    request = main.ParallelAgentsRequest(tasks=[f"task {index}" for index in range(5)], workers=99)

    result = await main.run_parallel_agents(request)

    assert result["workers"] == 5
    assert len(result["results"]) == 5
    assert peak == 5
