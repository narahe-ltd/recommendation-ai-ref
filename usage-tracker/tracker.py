import redis
import psycopg2
from time import sleep

redis_client = redis.Redis.from_url("redis://redis:6379")
conn = psycopg2.connect(
    dbname="bank_recommendations",
    user="bank_user",
    password="secure_password_123",
    host="postgres"
)

def track_usage():
    while True:
        # Get real-time usage from Redis queue
        usage_data = redis_client.blpop("usage_queue", timeout=5)
        if usage_data:
            _, data = usage_data
            customer_id, action = data.decode().split(":")
            
            # Store in PostgreSQL
            with conn.cursor() as cur:
                cur.execute("""
                    INSERT INTO usage_logs (customer_id, action, timestamp)
                    VALUES (%s, %s, NOW())
                """, (customer_id, action))
                conn.commit()
        
        sleep(0.1)

if __name__ == "__main__":
    track_usage()