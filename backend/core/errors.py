"""Consistent JSON errors: {"error": {"code": ..., "message": ..., "details": ...}}."""

import logging

from fastapi import FastAPI, HTTPException, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from sqlalchemy.exc import SQLAlchemyError

log = logging.getLogger("companion")


class AppError(Exception):
    def __init__(self, status: int, code: str, message: str, details: object | None = None):
        self.status, self.code, self.message, self.details = status, code, message, details


def _body(code: str, message: str, details: object | None = None) -> dict:
    return {"error": {"code": code, "message": message, "details": details}}


def register_error_handlers(app: FastAPI) -> None:
    @app.exception_handler(AppError)
    async def _app_error(_: Request, exc: AppError):
        return JSONResponse(_body(exc.code, exc.message, exc.details), status_code=exc.status)

    @app.exception_handler(HTTPException)
    async def _http_error(_: Request, exc: HTTPException):
        code = {401: "unauthorized", 403: "forbidden", 404: "not_found"}.get(exc.status_code, "http_error")
        return JSONResponse(
            _body(code, str(exc.detail)), status_code=exc.status_code, headers=exc.headers
        )

    @app.exception_handler(RequestValidationError)
    async def _validation(_: Request, exc: RequestValidationError):
        details = [
            {"loc": list(e.get("loc", [])), "msg": e.get("msg"), "type": e.get("type")}
            for e in exc.errors()
        ]
        return JSONResponse(_body("validation_error", "Invalid request", details), status_code=422)

    @app.exception_handler(SQLAlchemyError)
    async def _db_error(_: Request, exc: SQLAlchemyError):
        log.exception("database error: %s", exc)
        return JSONResponse(_body("database_error", "Database error, please retry"), status_code=503)

    @app.exception_handler(Exception)
    async def _unhandled(_: Request, exc: Exception):
        log.exception("unhandled error: %s", exc)
        return JSONResponse(_body("internal_error", "Something went wrong"), status_code=500)
