import copy
import json
import pytest
from unittest.mock import AsyncMock, patch, MagicMock
from adapters.openai_adapter import OpenAIAdapter
from adapters.anthropic_adapter import AnthropicAdapter
from adapters.openrouter_adapter import OpenRouterAdapter
from adapters.lmstudio_adapter import LMStudioAdapter
from adapters.ollama_adapter import OllamaAdapter


@pytest.mark.anyio
async def test_openai_capabilities():
    adapter = OpenAIAdapter(api_key="test-key")
    caps = await adapter.capabilities()
    assert caps["streaming"] is True
    assert caps["tool_calling"] is True
    assert caps["reasoning"] is True


@pytest.mark.anyio
async def test_anthropic_capabilities():
    adapter = AnthropicAdapter(api_key="test-key")
    caps = await adapter.capabilities()
    assert caps["streaming"] is True
    assert caps["tool_calling"] is True
    assert caps["reasoning"] is True


@pytest.mark.anyio
async def test_openrouter_capabilities():
    adapter = OpenRouterAdapter(api_key="test-key")
    caps = await adapter.capabilities()
    assert caps["streaming"] is True
    assert caps["tool_calling"] is True
    assert caps["reasoning"] is False


@pytest.mark.anyio
async def test_lmstudio_capabilities():
    adapter = LMStudioAdapter()
    caps = await adapter.capabilities()
    assert caps["streaming"] is True
    assert caps["tool_calling"] is True
    assert caps["reasoning"] is True


@pytest.mark.anyio
async def test_lmstudio_generate_sets_4096_token_limit():
    response = MagicMock()
    response.json.return_value = {"choices": [{"message": {"content": "ok"}}]}
    response.raise_for_status = MagicMock()

    with patch("httpx.AsyncClient.post", new_callable=AsyncMock, return_value=response) as post:
        await LMStudioAdapter().generate([{"role": "user", "content": "hello"}], "local-model")

    assert post.await_args.kwargs["json"]["max_tokens"] == 4096


@pytest.mark.anyio
async def test_lmstudio_continues_after_length_finish():
    calls = []

    class MockResponse:
        def __init__(self, lines):
            self.lines = lines

        async def __aenter__(self):
            return self

        async def __aexit__(self, *_args):
            return False

        def raise_for_status(self):
            pass

        async def aiter_lines(self):
            for line in self.lines:
                yield line

    class MockClient:
        def __init__(self, **_kwargs):
            pass

        async def __aenter__(self):
            return self

        async def __aexit__(self, *_args):
            return False

        def stream(self, _method, _url, **kwargs):
            calls.append(copy.deepcopy(kwargs["json"]))
            content = f"part {len(calls)}"
            finish = "length" if len(calls) <= 5 else "stop"
            lines = [
                "data: " + json.dumps({"choices": [{"delta": {"content": content}}]}),
                "data: " + json.dumps({"choices": [{"delta": {}, "finish_reason": finish}]}),
                "data: [DONE]",
            ]
            return MockResponse(lines)

    with patch("adapters.lmstudio_adapter.httpx.AsyncClient", MockClient):
        events = [event async for event in LMStudioAdapter().stream(
            [{"role": "user", "content": "hello"}], "local-model"
        )]

    assert [event["data"] for event in events if event["type"] == "token"] == [
        f"part {index}" for index in range(1, 7)
    ]
    assert len(calls) == 6
    assert all(call["max_tokens"] == 4096 for call in calls)
    assert calls[1]["messages"][-2]["content"] == "part 1"


@pytest.mark.anyio
async def test_lmstudio_generate_continues_and_aggregates_usage():
    calls = []

    class MockResponse:
        def __init__(self, content, finish_reason):
            self.content = content
            self.finish_reason = finish_reason

        def raise_for_status(self):
            pass

        def json(self):
            return {
                "choices": [{"message": {"content": self.content}, "finish_reason": self.finish_reason}],
                "usage": {"prompt_tokens": 2, "completion_tokens": 3, "total_tokens": 5},
            }

    class MockClient:
        def __init__(self, **_kwargs):
            pass

        async def __aenter__(self):
            return self

        async def __aexit__(self, *_args):
            return False

        async def post(self, _url, **kwargs):
            calls.append(copy.deepcopy(kwargs["json"]))
            content = f"part {len(calls)} "
            finish = "length" if len(calls) <= 5 else "stop"
            return MockResponse(content, finish)

    with patch("adapters.lmstudio_adapter.httpx.AsyncClient", MockClient):
        result = await LMStudioAdapter().generate(
            [{"role": "user", "content": "hello"}], "local-model"
        )

    assert result["content"].strip() == " ".join(f"part {index}" for index in range(1, 7))
    assert result["token_usage"] == {"prompt_tokens": 12, "completion_tokens": 18, "total_tokens": 30}
    assert len(calls) == 6
    assert calls[1]["max_tokens"] == 4096


@pytest.mark.anyio
async def test_ollama_capabilities():
    adapter = OllamaAdapter()
    caps = await adapter.capabilities()
    assert caps["streaming"] is True
    assert caps["tool_calling"] is False
    assert caps["reasoning"] is False


@pytest.mark.anyio
async def test_anthropic_list_models():
    adapter = AnthropicAdapter(api_key="test-key")
    models = await adapter.list_models()
    assert len(models) == 3
    ids = [m["id"] for m in models]
    assert "claude-sonnet-4-20250514" in ids
    assert "claude-haiku-4-20250414" in ids
    assert "claude-opus-4-20250514" in ids


@pytest.mark.anyio
async def test_openai_list_models():
    mock_response = MagicMock()
    mock_response.status_code = 200
    mock_response.json.return_value = {
        "data": [
            {"id": "gpt-4o", "object": "model"},
            {"id": "gpt-3.5-turbo", "object": "model"},
            {"id": "dall-e-3", "object": "model"},
            {"id": "o1-mini", "object": "model"},
        ]
    }
    mock_response.raise_for_status = MagicMock()

    adapter = OpenAIAdapter(api_key="test-key")
    with patch("httpx.AsyncClient.get", new_callable=AsyncMock, return_value=mock_response):
        models = await adapter.list_models()

    ids = [m["id"] for m in models]
    assert "gpt-4o" in ids
    assert "gpt-3.5-turbo" in ids
    assert "o1-mini" in ids
    assert "dall-e-3" not in ids


@pytest.mark.anyio
async def test_ollama_list_models():
    mock_response = MagicMock()
    mock_response.status_code = 200
    mock_response.json.return_value = {
        "models": [
            {"name": "llama3:latest"},
            {"name": "mistral:latest"},
        ]
    }
    mock_response.raise_for_status = MagicMock()

    adapter = OllamaAdapter()
    with patch("httpx.AsyncClient.get", new_callable=AsyncMock, return_value=mock_response):
        models = await adapter.list_models()

    assert len(models) == 2
    assert models[0]["id"] == "llama3:latest"
    assert models[1]["id"] == "mistral:latest"


@pytest.mark.anyio
async def test_openai_adapter_provider_name():
    adapter = OpenAIAdapter(api_key="test")
    assert adapter.provider_name == "openai"


@pytest.mark.anyio
async def test_anthropic_adapter_provider_name():
    adapter = AnthropicAdapter(api_key="test")
    assert adapter.provider_name == "anthropic"


@pytest.mark.anyio
async def test_openrouter_adapter_provider_name():
    adapter = OpenRouterAdapter(api_key="test")
    assert adapter.provider_name == "openrouter"


@pytest.mark.anyio
async def test_lmstudio_adapter_provider_name():
    adapter = LMStudioAdapter()
    assert adapter.provider_name == "lmstudio"


@pytest.mark.anyio
async def test_ollama_adapter_provider_name():
    adapter = OllamaAdapter()
    assert adapter.provider_name == "ollama"
