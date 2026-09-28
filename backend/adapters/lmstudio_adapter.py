import re
import json
import httpx
from typing import AsyncGenerator
from .base import BaseAdapter

DEFAULT_MAX_TOKENS = 4096


class LMStudioAdapter(BaseAdapter):
    provider_name = "lmstudio"

    def __init__(self, base_url: str = "http://localhost:1234/v1"):
        base_url = base_url.rstrip("/")
        if not base_url.endswith("/v1"):
            base_url += "/v1"
        self.base_url = base_url

    def _headers(self) -> dict:
        return {"Content-Type": "application/json"}

    async def capabilities(self) -> dict:
        return {
            "streaming": True,
            "tool_calling": True,
            "reasoning": True,
            "models": [],
        }

    def _apply_no_think(self, messages: list[dict], reasoning_enabled: bool) -> list[dict]:
        if reasoning_enabled:
            return messages
        messages = [m.copy() for m in messages]
        for i in range(len(messages) - 1, -1, -1):
            if messages[i]["role"] == "user":
                messages[i]["content"] = messages[i]["content"] + " /no_think"
                break
        return messages

    async def list_models(self) -> list[dict]:
        async with httpx.AsyncClient(timeout=10) as client:
            resp = await client.get(f"{self.base_url}/models", headers=self._headers())
            resp.raise_for_status()
            data = resp.json().get("data", [])
        return [{"name": m["id"], "id": m["id"]} for m in data]

    async def generate(self, messages: list[dict], model: str, **kwargs) -> dict:
        reasoning_enabled = kwargs.get("reasoning_enabled", False)
        continuation_messages = self._apply_no_think(messages, reasoning_enabled)
        max_tokens = kwargs.get("max_tokens", DEFAULT_MAX_TOKENS)
        tools = kwargs.get("tools")
        response_parts = []
        usage = {"prompt_tokens": 0, "completion_tokens": 0, "total_tokens": 0}
        while True:
            payload = {
                "model": model,
                "messages": continuation_messages,
                "max_tokens": max_tokens,
            }
            if tools:
                payload["tools"] = tools
            async with httpx.AsyncClient(timeout=httpx.Timeout(300, connect=30)) as client:
                resp = await client.post(
                    f"{self.base_url}/chat/completions",
                    headers=self._headers(),
                    json=payload,
                )
                resp.raise_for_status()
                data = resp.json()

            choice = data["choices"][0]
            completion = choice["message"].get("content", "") or ""
            response_parts.append(completion)
            for key in usage:
                usage[key] += data.get("usage", {}).get(key, 0)

            tool_response = choice["message"].get("tool_calls")
            if choice.get("finish_reason") == "length":
                if tool_response:
                    raise RuntimeError("Model truncated a tool call; incomplete arguments were not executed.")
                continuation_messages.append({"role": "assistant", "content": completion})
                continuation_prompt = "Continue directly from the last emitted text without repeating it. Finish the response."
                if not reasoning_enabled:
                    continuation_prompt += " /no_think"
                continuation_messages.append({"role": "user", "content": continuation_prompt})
                continue
            break

        content = "".join(response_parts)
        if not reasoning_enabled:
            content = re.sub(r"<think>[\s\S]*?</think>\s*", "", content)

        tool_calls = None
        if tool_response:
            tool_calls = [
                {
                    "id": tc.get("id", f"call_{i}"),
                    "name": tc["function"]["name"],
                    "arguments": tc["function"]["arguments"],
                }
                for i, tc in enumerate(tool_response)
            ]

        return {
            "content": content,
            "role": "assistant",
            "token_usage": {
                "prompt_tokens": usage.get("prompt_tokens", 0),
                "completion_tokens": usage.get("completion_tokens", 0),
                "total_tokens": usage.get("total_tokens", 0),
            },
            "tool_calls": tool_calls,
        }

    async def stream(self, messages: list[dict], model: str, **kwargs) -> AsyncGenerator[dict, None]:
        reasoning_enabled = kwargs.get("reasoning_enabled", False)
        continuation_messages = self._apply_no_think(messages, reasoning_enabled)
        max_tokens = kwargs.get("max_tokens", DEFAULT_MAX_TOKENS)
        tools = kwargs.get("tools")
        while True:
            payload = {
                "model": model,
                "messages": continuation_messages,
                "stream": True,
                "max_tokens": max_tokens,
            }
            if tools:
                payload["tools"] = tools
            in_think = False
            tool_calls_buf = {}
            response_parts = []
            finish_reason = None
            continue_response = False
            async with httpx.AsyncClient(timeout=httpx.Timeout(300, connect=30)) as client:
                async with client.stream(
                    "POST",
                    f"{self.base_url}/chat/completions",
                    headers=self._headers(),
                    json=payload,
                ) as resp:
                    resp.raise_for_status()
                    async for line in resp.aiter_lines():
                        if not line.startswith("data: "):
                            continue
                        data_str = line[6:]
                        if data_str.strip() == "[DONE]":
                            if finish_reason == "length" and tool_calls_buf:
                                yield {"type": "error", "data": "Model truncated a tool call; incomplete arguments were not executed."}
                                yield {"type": "done", "data": None}
                                return
                            if finish_reason == "length":
                                continuation_messages.append({"role": "assistant", "content": "".join(response_parts)})
                                continuation_prompt = "Continue directly from the last emitted text without repeating it. Finish the response."
                                if not reasoning_enabled:
                                    continuation_prompt += " /no_think"
                                continuation_messages.append({"role": "user", "content": continuation_prompt})
                                continue_response = True
                                break
                            for tc in tool_calls_buf.values():
                                yield {"type": "tool_call", "data": tc}
                            yield {"type": "done", "data": None}
                            return
                        try:
                            chunk = json.loads(data_str)
                        except json.JSONDecodeError:
                            continue

                        choices = chunk.get("choices", [])
                        if not choices:
                            continue
                        choice = choices[0]
                        finish_reason = choice.get("finish_reason") or finish_reason
                        delta = choice.get("delta", {})

                        if delta.get("tool_calls"):
                            for tc_delta in delta["tool_calls"]:
                                idx = tc_delta.get("index", 0)
                                if idx not in tool_calls_buf:
                                    tool_calls_buf[idx] = {"id": tc_delta.get("id", f"call_{idx}"), "name": "", "arguments": ""}
                                if tc_delta.get("id"):
                                    tool_calls_buf[idx]["id"] = tc_delta["id"]
                                if tc_delta.get("function", {}).get("name"):
                                    tool_calls_buf[idx]["name"] = tc_delta["function"]["name"]
                                if tc_delta.get("function", {}).get("arguments"):
                                    tool_calls_buf[idx]["arguments"] += tc_delta["function"]["arguments"]
                            continue

                        content = delta.get("content", "")
                        if not content:
                            continue
                        response_parts.append(content)

                        if not reasoning_enabled:
                            if "<think>" in content:
                                in_think = True
                                content = content.split("<think>")[0]
                                if content:
                                    yield {"type": "token", "data": content}
                                continue
                            if in_think:
                                if "</think>" in content:
                                    in_think = False
                                    content = content.split("</think>", 1)[1]
                                    if content:
                                        yield {"type": "token", "data": content}
                                continue

                        yield {"type": "token", "data": content}
            if continue_response:
                continue
