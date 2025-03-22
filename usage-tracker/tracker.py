import redis
import psycopg2
from time import sleep
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

redis_client = redis.Redis.from_url("redis://redis:6379")
conn = psycopg2.connect(
    dbname="bank_recommendations",
    user="bank_user",
    password="secure_password_123",
    host="postgres"
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