# simulate_usage.py
import redis
import time
import random

redis_client = redis.Redis.from_url("redis://redis:6379")
actions = [
    "used mobile app for transfer",
    "applied for travel credit card",
    "made online payment",
    "checked investment options",
    "used ATM"
]
customers = ["cust001", "cust002", "cust003", "cust004", "cust005"]

for _ in range(10):  # Simulate 10 events
    customer = random.choice(customers)
    action = random.choice(actions)
    redis_client.lpush("usage_queue", f"{customer}:{action}")
    print(f"Added event: {customer}:{action}")
    time.sleep(2)  # Delay between events