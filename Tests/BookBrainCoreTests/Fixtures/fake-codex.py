#!/usr/bin/env python3
"""Deterministic app-server peer for transport and lifecycle tests; no network."""

import base64
import json
import os
import sys
import uuid
from pathlib import Path


def emit(message):
    payload = (json.dumps(message, ensure_ascii=False) + "\n").encode()
    # Deliberately split reads, including multibyte text.
    for index in range(0, len(payload), 7):
        os.write(sys.stdout.fileno(), payload[index : index + 7])


def event(method, **params):
    if method == "turn/completed":
        params["turn"]["id"] = turn_id
    emit(
        {
            "method": method,
            "params": {"threadId": thread_id, "turnId": turn_id, **params},
        }
    )


for line in sys.stdin:
    request = json.loads(line)
    method = request.get("method")
    request_id = request.get("id")
    params = request.get("params", {})
    result = {}
    if method == "initialize":
        assert "features.image_generation=true" in sys.argv
        assert "features.shell_tool=false" in sys.argv
        assert "features.unified_exec=false" in sys.argv
        assert "features.view_image=false" in sys.argv
        assert "features.memories=true" in sys.argv
        assert "memories.use_memories=true" in sys.argv
        assert "memories.generate_memories=true" in sys.argv
        assert (
            "features.memory_tool=false" not in sys.argv
        )  # Legacy alias for memories.
        result = {"userAgent": "fake-codex"}
    elif method == "account/read":
        result = {"account": {"type": "chatgpt"}, "requiresOpenaiAuth": True}
    elif method == "model/list":
        second_page = params.get("cursor") == "second"
        model = "standard-model" if second_page else "gpt-6.1-terra"
        effort = "medium" if second_page else "xhigh"
        result = {
            "data": [
                {
                    "model": model,
                    "displayName": model,
                    "isDefault": not second_page,
                    "serviceTiers": [] if second_page else [{"id": "priority"}],
                    "defaultReasoningEffort": effort,
                    "supportedReasoningEfforts": [{"reasoningEffort": effort}],
                }
            ],
            "nextCursor": None if second_page else "second",
        }
    elif method == "config/read":
        result = {"config": {"mcp_servers": {"private_server": {"enabled": True}}}}
    elif method in ("thread/start", "thread/resume"):
        if method == "thread/start":
            thread_id = str(uuid.uuid4())
            assert params["dynamicTools"][0]["name"] == "book_pdf"
        else:
            thread_id = params["threadId"]
            assert params["excludeTurns"] is True
        selected = (
            params["model"],
            params["serviceTier"],
            params["config"]["model_reasoning_effort"],
        )
        assert not params.get("ephemeral", False)
        assert params["approvalPolicy"] == "never"
        assert params["permissions"] == "book-brain"
        assert params["config"]["mcp_servers"]["private_server"]["enabled"] is False
        result = {
            "thread": {"id": thread_id},
            "activePermissionProfile": {"id": "book-brain"},
            "approvalPolicy": "never",
        }
    elif method == "turn/start":
        assert params["permissions"] == "book-brain"
        prompt = json.loads(params["input"][0]["text"])
        question = prompt["current_question"]
        expected = {
            "STANDARD_MODEL": ("standard-model", None, "medium"),
            "FAST_OFF": ("gpt-6.1-terra", None, "xhigh"),
        }.get(question, ("gpt-6.1-terra", "priority", "xhigh"))
        assert selected == expected
        assert (params["model"], params["serviceTier"], params["effort"]) == expected
        if question == "ATTACHMENTS":
            images = [item for item in params["input"] if item["type"] == "image"]
            assert len(images) == 1
            assert images[0]["url"].startswith("data:image/png;base64,")
            files = [
                json.loads(item["text"])
                for item in params["input"][1:]
                if item["type"] == "text" and item["text"].startswith("{")
            ]
            assert files[0]["untrusted_contents"] == "Synthetic attachment notes."
            assert len(prompt["chat_attachments"]) == 2
            assert prompt["recent_exchanges"][0]["question"] == "Earlier question"
        assert params["threadId"] == thread_id
        turn_id = str(uuid.uuid4())
        emit(
            {
                "method": "item/agentMessage/delta",
                "params": {
                    "threadId": thread_id,
                    "turnId": "earlier-turn",
                    "itemId": "stale",
                    "delta": "LEAK",
                },
            }
        )
        emit({"id": request_id, "result": {"turn": {"id": turn_id}}})
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
        if question in ("IMAGE", "IMAGE_FILE", "IMAGE_INVALID_PATH"):
            item = {"id": "ig_test", "type": "imageGeneration", "status": "in_progress"}
            event("item/started", item=item)
            item["status"] = "completed"
            png = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+j6h8AAAAASUVORK5CYII="
            if question == "IMAGE":
                item["result"] = png
            else:
                item["fileId"] = "synthetic-image"
                root = Path.cwd()
                if question == "IMAGE_FILE":
                    root = root / "generated_images"
                    root.mkdir(exist_ok=True)
                path = root / "ig_test.png"
                path.write_bytes(base64.b64decode(png))
                item["savedPath"] = str(path)
            event("item/completed", item=item)
            event("turn/completed", turn={"status": "completed"})
            continue
        if question == "EMPTY":
            event("turn/completed", turn={"status": "completed"})
            continue
        if question == "MALFORMED":
            os.write(sys.stdout.fileno(), b"not-json\n")
            continue
        if question == "PDF_SCOPE":
            pdf_call = {
                "threadId": thread_id,
                "turnId": turn_id,
                "namespace": "book_pdf",
                "tool": "read_book_page",
                "arguments": {"page": 1},
            }
            for override in (
                {"threadId": "another-book"},
                {"turnId": "finished-turn"},
                {"namespace": "unknown"},
                {"tool": "unknown"},
            ):
                emit(
                    {
                        "id": "pdf-check",
                        "method": "item/tool/call",
                        "params": {**pdf_call, **override},
                    }
                )
                assert json.loads(next(sys.stdin))["error"]["code"] == -32601
            event("item/started", item={"id": "web", "type": "webSearch"})
        if question == "CHAT_PDF_SCOPE":
            attachment_id = prompt["chat_attachments"][0]["id"]
            for selected_id, success in (
                (attachment_id, True),
                ("another-chat", False),
            ):
                emit(
                    {
                        "id": "chat-pdf-check",
                        "method": "item/tool/call",
                        "params": {
                            "threadId": thread_id,
                            "turnId": turn_id,
                            "namespace": "book_pdf",
                            "tool": "read_book_page",
                            "arguments": {"page": 1, "attachment_id": selected_id},
                        },
                    }
                )
                response = json.loads(next(sys.stdin))["result"]
                assert response["success"] is success
                if success:
                    assert "amber" in response["contentItems"][0]["text"]
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
        event("item/agentMessage/delta", itemId="answer", delta="Hello, ")
        event("item/agentMessage/delta", itemId="answer", delta="reader! 📖")
        event(
            "item/completed",
            item={
                "id": "answer",
                "type": "agentMessage",
                "text": "Hello, reader! 📖 Your context is saved.",
                "phase": "final_answer",
            },
        )
        event("turn/completed", turn={"status": "completed"})
        continue
    if request_id is not None:
        emit({"id": request_id, "result": result})
