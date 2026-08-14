import asyncio
from sqlalchemy import select
from app.database import AsyncSessionLocal
from app.models import User

async def promote_user(email: str):
    async with AsyncSessionLocal() as db:
        result = await db.execute(select(User).where(User.email == email))
        user = result.scalar_one_or_none()
        if not user:
            print(f"User with email {email} not found.")
            return
            
        user.is_admin = True
        await db.commit()
        print(f"User {email} is now an Admin!")

if __name__ == "__main__":
    import sys
    if len(sys.argv) < 2:
        print("Usage: python promote_admin.py <email>")
    else:
        asyncio.run(promote_user(sys.argv[1]))
