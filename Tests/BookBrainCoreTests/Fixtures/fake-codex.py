#!/usr/bin/env python3
"""Deterministic app-server peer for transport and lifecycle tests; no network."""

import json
import os
import sys


def emit(message):
    payload = (json.dumps(message, ensure_ascii=False) + "\n").encode()
    # Deliberately split reads, including multibyte text.
    for index in range(0, len(payload), 7):
        os.write(sys.stdout.fileno(), payload[index : index + 7])


def event(method, **params):
    emit({"method": method, "params": {"threadId": "test-thread", **params}})


for line in sys.stdin:
    request = json.loads(line)
    method = request.get("method")
    request_id = request.get("id")
    params = request.get("params", {})
    result = {}
    if method == "initialize":
        assert "features.memories=true" in sys.argv
        assert "memories.use_memories=true" in sys.argv
        assert "memories.generate_memories=true" in sys.argv
        assert (
            "features.memory_tool=false" not in sys.argv
        )  # Legacy alias for memories.
        result = {"userAgent": "fake-codex"}
    elif method == "account/read":
        result = {"account": {"type": "chatgpt"}, "requiresOpenaiAuth": True}
    elif method == "config/read":
        result = {"config": {"mcp_servers": {"private_server": {"enabled": True}}}}
    elif method == "thread/start":
        assert params["model"] == "gpt-6.1-terra"
        assert params["config"]["model_reasoning_effort"] == "xhigh"
        assert params["serviceTier"] == "priority"
        assert not params.get("ephemeral", False)
        assert params["approvalPolicy"] == "never"
        assert params["permissions"] == "book-brain"
        assert params["config"]["mcp_servers"]["private_server"]["enabled"] is False
        result = {
            "thread": {"id": "test-thread"},
            "activePermissionProfile": {"id": "book-brain"},
            "approvalPolicy": "never",
        }
    elif method == "turn/start":
        assert params["permissions"] == "book-brain"
        question = json.loads(params["input"][0]["text"])["current_question"]
        emit({"id": request_id, "result": {"turn": {"id": "test-turn"}}})
        if question == "EXIT":
            sys.exit(1)
        if question == "HANG":
            continue
        if question == "TOOL":
            event("item/started", item={"id": "tool", "type": "commandExecution"})
            continue
        if question == "FAIL":
            event(
                "turn/completed",
                turn={"status": "failed", "error": {"message": "rate limit test"}},
            )
            continue
        if question == "EMPTY":
            event("turn/completed", turn={"status": "completed"})
            continue
        if question == "MALFORMED":
            os.write(sys.stdout.fileno(), b"not-json\n")
            continue
        if question == "SERVER_REQUEST":
            emit(
                {"id": "approval-1", "method": "item/commandExecution/requestApproval"}
            )
            refusal = json.loads(next(sys.stdin))
            assert refusal["error"]["code"] == -32601
        emit(
            {
                "method": "item/agentMessage/delta",
                "params": {
                    "threadId": "another-book",
                    "itemId": "other",
                    "delta": "LEAK",
                },
            }
        )
        event(
            "item/started",
            item={
                "id": "comment",
                "type": "agentMessage",
                "text": "",
                "phase": "commentary",
            },
        )
        event("item/agentMessage/delta", itemId="comment", delta="Hidden commentary")
        event(
            "item/started",
            item={
                "id": "answer",
                "type": "agentMessage",
                "text": "",
                "phase": "final_answer",
            },
        )
        event("item/agentMessage/delta", itemId="answer", delta="Olá, ")
        event("item/agentMessage/delta", itemId="answer", delta="leitor.")
        event(
            "item/completed",
            item={
                "id": "answer",
                "type": "agentMessage",
                "text": "Olá, leitor. Contexto preservado.",
                "phase": "final_answer",
            },
        )
        event("turn/completed", turn={"status": "completed"})
        continue
    if request_id is not None:
        emit({"id": request_id, "result": result})
