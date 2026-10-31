import asyncio

import models  # noqa: F401  (registers tables on Base)
from core.db import Base, engine


async def main():
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    await engine.dispose()
    print("Tables created")


if __name__ == "__main__":
    asyncio.run(main())