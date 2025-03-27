import redis
import psycopg2
from time import sleep
import logging
from dotenv import load_dotenv
import os
from pydantic import BaseModel, Field
from pydantic_settings import BaseSettings

# Load environment variables from .env file
load_dotenv()

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class Settings(BaseSettings):
    redis_url: str = Field(..., env="REDIS_URL")
    db_name: str = Field(..., env="DB_NAME")
    db_user: str = Field(..., env="DB_USER")
    db_password: str = Field(..., env="DB_PASSWORD")
    db_host: str = Field(..., env="DB_HOST")
    db_port: int = Field(..., env="DB_PORT")

settings = Settings()

redis_client = redis.Redis.from_url(settings.redis_url)
conn = psycopg2.connect(
    dbname=settings.db_name,
    user=settings.db_user,
    password=settings.db_password,
    host=settings.db_host,
    port=settings.db_port
)

def update_customer_history(customer_id: str, action: str):
    """Update customer's transaction history with new action."""
    try:
        with conn.cursor() as cur:
            # Append action to transaction_history
            cur.execute("""
                UPDATE customers 
                SET transaction_history = COALESCE(transaction_history, '') || ', ' || %s,
                    embedding = NULL  -- Reset embedding to trigger recalculation
                WHERE customer_id = %s
            """, (action, customer_id))
            conn.commit()
            logger.info(f"Updated transaction history for {customer_id} with action: {action}")
    except Exception as e:
        logger.error(f"Error updating customer history: {str(e)}")
        conn.rollback()

def track_usage():
    logger.info("Starting usage tracker...")
    while True:
        # Get real-time usage from Redis queue
        usage_data = redis_client.blpop("usage_queue", timeout=5)
        if usage_data:
            _, data = usage_data
            try:
                customer_id, action = data.decode().split(":", 1)
                # Log the usage event
                with conn.cursor() as cur:
                    cur.execute("""
                        INSERT INTO usage_logs (customer_id, action, timestamp)
                        VALUES (%s, %s, NOW())
                    """, (customer_id, action))
                    conn.commit()
                # Update customer history
                update_customer_history(customer_id, action)
                logger.info(f"Processed usage event for {customer_id}: {action}")
            except ValueError:
                logger.error(f"Invalid usage data format: {data.decode()}")
            except Exception as e:
                logger.error(f"Error processing usage event: {str(e)}")
                conn.rollback()
        sleep(0.1)

if __name__ == "__main__":
    try:
        track_usage()
    except KeyboardInterrupt:
        conn.close()
        logger.info("Usage tracker stopped")