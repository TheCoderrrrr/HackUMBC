"""Shared error envelope (BACKEND.md section 4) and FastAPI handlers."""
from __future__ import annotations

import logging

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException as StarletteHTTPException

log = logging.getLogger("adaptive_retirement")


class ApiError(Exception):
    def __init__(self, status: int, code: str, message: str, field_paths: list[str] | None = None, retryable: bool = False):
        super().__init__(message)
        self.status, self.code, self.message = status, code, message
        self.field_paths, self.retryable = field_paths or [], retryable


def envelope(status: int, code: str, message: str, field_paths: list[str] | None = None, retryable: bool = False) -> JSONResponse:
    body = {"error": {"code": code, "message": message, "field_paths": field_paths or [], "retryable": retryable}}
    return JSONResponse(status_code=status, content=body)


def _field_path(loc: tuple) -> str:
    loc = list(loc)
    if loc and loc[0] == "body":
        loc = loc[1:]
        if loc and not isinstance(loc[0], str):  # JSON decode errors carry a character offset
            loc = loc[1:]
    if loc and loc[0] == "profile":
        loc = loc[1:]
    return ".".join(str(p) for p in loc)


def _message(err: dict) -> str:
    msg = err.get("msg", "Invalid value.")
    return msg.removeprefix("Value error, ")


def install_error_handlers(app: FastAPI) -> None:
    @app.exception_handler(ApiError)
    def _api_error(_: Request, exc: ApiError) -> JSONResponse:
        return envelope(exc.status, exc.code, exc.message, exc.field_paths, exc.retryable)

    @app.exception_handler(RequestValidationError)
    def _validation(_: Request, exc: RequestValidationError) -> JSONResponse:
        errors = exc.errors()
        if any(e.get("type") == "json_invalid" for e in errors):
            return envelope(422, "INVALID_REQUEST", "Request body is not valid JSON.")
        paths = [p for p in (_field_path(tuple(e.get("loc", ()))) for e in errors) if p]
        in_profile = any(len(e.get("loc", ())) > 1 and e["loc"][1] == "profile" for e in errors)
        code = "INVALID_PROFILE" if in_profile else "INVALID_REQUEST"
        return envelope(422, code, _message(errors[0]) if errors else "Invalid request.", paths)

    @app.exception_handler(StarletteHTTPException)
    def _http(_: Request, exc: StarletteHTTPException) -> JSONResponse:
        if exc.status_code == 400:  # e.g. undecodable body: keep to the contract's 422
            return envelope(422, "INVALID_REQUEST", "Request body could not be read.")
        code = {404: "NOT_FOUND", 405: "METHOD_NOT_ALLOWED"}.get(exc.status_code, "HTTP_ERROR")
        return envelope(exc.status_code, code, str(exc.detail))

    @app.exception_handler(Exception)
    def _unexpected(_: Request, exc: Exception) -> JSONResponse:
        log.error("unexpected error: %s", type(exc).__name__)
        return envelope(500, "INTERNAL_ERROR", "Something went wrong. Please try again.", retryable=True)
