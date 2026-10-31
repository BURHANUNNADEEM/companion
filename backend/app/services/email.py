"""E-mail sending for caregiver invites (F9). `console` backend logs; `smtp` uses e.g. a Gmail app password."""
from __future__ import annotations

import asyncio
import logging
import smtplib
from email.message import EmailMessage

from app.core.config import get_settings

log = logging.getLogger("companion.email")
OUTBOX: list[dict] = []  # console backend keeps sent mail here (useful for tests/demo)


def _send_smtp(msg: EmailMessage) -> None:
    s = get_settings()
    with smtplib.SMTP(s.smtp_host, s.smtp_port, timeout=15) as server:
        if s.smtp_use_tls:
            server.starttls()
        if s.smtp_username:
            server.login(s.smtp_username, s.smtp_password)
        server.send_message(msg)


async def send_email(to: str, subject: str, body: str) -> bool:
    s = get_settings()
    if s.email_backend == "console":
        OUTBOX.append({"to": to, "subject": subject, "body": body})
        log.info("EMAIL to=%s subject=%s\n%s", to, subject, body)
        return True
    msg = EmailMessage()
    msg["From"] = s.smtp_from
    msg["To"] = to
    msg["Subject"] = subject
    msg.set_content(body)
    try:
        await asyncio.to_thread(_send_smtp, msg)
        return True
    except (smtplib.SMTPException, OSError) as exc:
        log.error("smtp send failed: %s", exc)
        return False
