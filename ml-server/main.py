from fastapi import FastAPI, HTTPException, BackgroundTasks, Depends, Request
from fastapi.security import APIKeyHeader
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
from pydantic_settings import BaseSettings
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.util import get_remote_address
import redis
import psycopg2.pool
from sentence_transformers import SentenceTransformer
import numpy as np
import logging
import time
import os
from dotenv import load_dotenv
import random
import asyncio
import aiohttp
import json
from typing import List, Optional, Dict

# Load environment variables
load_dotenv()

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class JsonFormatter(logging.Formatter):
    def format(self, record):
        return json.dumps({"time": self.formatTime(record), "level": record.levelname, "message": record.msg})

# Ensure a handler exists before setting formatter
if not logger.handlers:  # Check if handlers are empty
    handler = logging.StreamHandler()
    handler.setFormatter(JsonFormatter())
    logger.addHandler(handler)
else:
    logger.handlers[0].setFormatter(JsonFormatter())

# Configuration via environment variables
class Settings(BaseSettings):
    openai_api_key: str
    postgres_db: str = "bank_recommendations"
    postgres_user: str = "bank_user"
    postgres_password: str
    postgres_port: int = 5432
    postgres_host: str = "postgres"
    redis_url: str = "redis://redis:6379"
    api_key: str  # For endpoint authentication
    cors_allow_origins: str = "*"  # Comma-separated list in .env
    openai_api_url: str = "https://api.openai.com/v1/chat/completions"

    class Config:
        env_file = ".env"
        extra = "ignore"

settings = Settings()

app = FastAPI()
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_allow_origins.split(","),
    allow_methods=["*"],
    allow_headers=["*"]
)
app.state.limiter = Limiter(key_func=get_remote_address)
app.add_exception_handler(429, _rate_limit_exceeded_handler)

# Pydantic model for simulation request with validation
class SimulateRequest(BaseModel):
    customers: Optional[List[str]] = None
    num_events: int = Field(default=10, ge=1, le=100)
    delay: float = Field(default=2.0, ge=0.1, le=10.0)

# Initialize SentenceTransformer model
def load_model(max_retries: int = 3, retry_delay: int = 10) -> SentenceTransformer:
    for attempt in range(max_retries):
        try:
            logger.info(f"Attempting to load model (attempt {attempt + 1}/{max_retries})")
            return SentenceTransformer('all-MiniLM-L6-v2')
        except Exception as e:
            if attempt == max_retries - 1:
                logger.error(f"Failed to load model after {max_retries} attempts: {str(e)}")
                raise
            logger.warning(f"Failed to load model (attempt {attempt + 1}): {str(e)}")
            time.sleep(retry_delay)

try:
    model = load_model()
    logger.info("Model loaded successfully")
except Exception as e:
    logger.error(f"Failed to initialize model: {str(e)}")
    raise

# logger.info(f"Redis URL: {settings.redis_url}")
# logger.info(f"API Key: {settings.api_key}")
# logger.info(f"Database URL: {settings.postgres_db}")
# logger.info(f"Database User: {settings.postgres_user}")
# logger.info(f"Database Host: {settings.postgres_host}")
# logger.info(f"Database Port: {settings.postgres_port}")

# Database and Redis connections
db_pool = psycopg2.pool.SimpleConnectionPool(1, 20,
    dbname=settings.postgres_db,
    user=settings.postgres_user,
    password=settings.postgres_password,
    host=settings.postgres_host,
    port=settings.postgres_port
)
redis_client = redis.Redis.from_url(settings.redis_url)

# API Key authentication
api_key_header = APIKeyHeader(name="X-API-Key")
async def verify_api_key(api_key: str = Depends(api_key_header)):
    if api_key != settings.api_key:
        raise HTTPException(status_code=401, detail="Invalid API Key")
    return api_key

def generate_embedding(text: str) -> List[float]:
    """Generate embedding from text, handling empty inputs."""
    if not text.strip():
        logger.warning("Empty text provided for embedding, using default empty string")
        text = ""
    return model.encode(text).tolist()

async def update_embedding(customer_id: str, text: str, conn):
    """Background task to update customer embedding."""
    embedding = generate_embedding(text)
    cur = conn.cursor()
    cur.execute("UPDATE customers SET embedding = %s::vector WHERE customer_id = %s", (embedding, customer_id))
    conn.commit()
    cur.close()

async def generate_recommendation_explanation(customer_data: tuple, products: List[tuple]) -> str:
    """Generate explanation using ChatGPT with retries and caching."""
    transaction_history, preferences = customer_data
    cache_key = f"exp:{hash(str(customer_data) + str(products))}"
    cached = redis_client.get(cache_key)
    if cached:
        logger.info("Returning cached explanation")
        return cached.decode()
    
    product_str = "\n".join([f"- {p[0]}: {p[1]}" for p in products])
    prompt = (
        f"Customer Profile:\n"
        f"Transaction History: {transaction_history}\n"
        f"Preferences: {preferences}\n\n"
        f"Recommended Products:\n{product_str}\n\n"
        f"Explain in a concise, friendly tone why these products are suitable for this customer."
    )
    
    for attempt in range(3):
        try:
            async with aiohttp.ClientSession() as session:
                async with session.post(
                    settings.openai_api_url,
                    headers={
                        "Authorization": f"Bearer {settings.openai_api_key}",
                        "Content-Type": "application/json"
                    },
                    json={
                        "model": "gpt-3.5-turbo",
                        "messages": [
                            {"role": "system", "content": "You are a helpful banking assistant."},
                            {"role": "user", "content": prompt}
                        ],
                        "max_tokens": 150,
                        "temperature": 0.7
                    }
                ) as response:
                    result = await response.json()
                    if "choices" in result and len(result["choices"]) > 0:
                        explanation = result["choices"][0]["message"]["content"].strip()
                        redis_client.setex(cache_key, 3600, explanation)
                        return explanation
                    else:
                        logger.error(f"OpenAI API error: {result}")
        except Exception as e:
            if attempt == 2:
                logger.error(f"Failed after 3 attempts: {str(e)}")
                return "Sorry, I couldn’t generate a detailed explanation at this time."
            await asyncio.sleep(2 ** attempt)  # Exponential backoff

# Default actions for simulation
DEFAULT_ACTIONS = [
    "used mobile app for transfer",
    "applied for travel credit card",
    "made online payment",
    "checked investment options",
    "used ATM",
    "viewed loan rates",
    "deposited check via app",
    "activated cashback offer"
]

@app.get("/")
async def root():
    return {"status": "healthy", "model": "all-MiniLM-L6-v2"}

@app.get("/health")
async def health_check():
    conn = db_pool.getconn()
    try:
        cur = conn.cursor()
        cur.execute("SELECT 1")
        redis_client.ping()
        return {"status": "healthy", "database": "ok", "redis": "ok"}
    except Exception as e:
        logger.error(f"Health check failed: {str(e)}")
        return {"status": "unhealthy", "error": str(e)}
    finally:
        cur.close()
        db_pool.putconn(conn)

@app.post("/encode", dependencies=[Depends(verify_api_key)])
@app.state.limiter.limit("10/minute")
async def encode_text(request: Request, texts: List[str]) -> Dict[str, List[List[float]]]:
    try:
        embeddings = model.encode(texts)
        return {"embeddings": embeddings.tolist()}
    except Exception as e:
        logger.error(f"Error during text encoding: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/recommendations/{customer_id}", dependencies=[Depends(verify_api_key)])
@app.state.limiter.limit("10/minute")
async def get_recommendations(request: Request, customer_id: str, background_tasks: BackgroundTasks):  # Added request parameter
    conn = db_pool.getconn()
    try:
        cur = conn.cursor()
        cur.execute("""
            SELECT transaction_history, preferences, embedding 
            FROM customers 
            WHERE customer_id = %s
        """, (customer_id,))
        customer_data = cur.fetchone()
        
        if not customer_data:
            logger.warning(f"Customer {customer_id} not found")
            raise HTTPException(status_code=404, detail="Customer not found")
        
        # Generate or use existing embedding
        if customer_data[2] is None:
            text = (customer_data[0] or "") + " " + (customer_data[1] or "")
            background_tasks.add_task(update_embedding, customer_id, text, conn)
            embedding = generate_embedding(text)  # Fallback for immediate use
        else:
            embedding = customer_data[2]
            logger.info(f"Using existing embedding for customer {customer_id}")
        
        # Get similar products/services, casting the input embedding to vector
        cur.execute("""
            SELECT product_id, description 
            FROM products 
            ORDER BY embedding <=> %s::vector 
            LIMIT 5
        """, (embedding,))
        recommendations = cur.fetchall()
        logger.info(f"Found {len(recommendations)} recommendations for {customer_id}")
        
        # Generate explanation using ChatGPT
        explanation = await generate_recommendation_explanation(
            (customer_data[0], customer_data[1]), recommendations
        )
        # Cache results
        redis_client.setex(f"recs:{customer_id}", 3600, str(recommendations))
        logger.info(f"Recommendations cached for customer {customer_id}")
        
        return {
            "customer_id": customer_id,
            "recommendations": recommendations,
            "explanation": explanation
        }
    
    except psycopg2.Error as e:
        logger.error(f"Database error: {str(e)}")
        conn.rollback()
        raise HTTPException(status_code=500, detail="Database error")
    except Exception as e:
        logger.error(f"Unexpected error: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        cur.close()
        db_pool.putconn(conn)

@app.on_event("startup")
async def startup_event():
    """Initialize product embeddings on startup."""
    conn = db_pool.getconn()
    try:
        cur = conn.cursor()
        cur.execute("SELECT product_id, description, embedding FROM products")
        products = cur.fetchall()
        logger.info(f"Found {len(products)} products to process")
        
        updated = 0
        for prod_id, desc, emb in products:
            if emb is None and desc:
                embedding = generate_embedding(desc)
                cur.execute("""
                    UPDATE products 
                    SET embedding = %s::vector 
                    WHERE product_id = %s
                """, (embedding, prod_id))
                updated += 1
                logger.info(f"Generated embedding for product {prod_id}")
        conn.commit()
        logger.info(f"Updated embeddings for {updated} products")
    except Exception as e:
        logger.error(f"Error during startup: {str(e)}")
        conn.rollback()
    finally:
        cur.close()
        db_pool.putconn(conn)

@app.post("/simulate_usage", dependencies=[Depends(verify_api_key)])
@app.state.limiter.limit("5/minute")
async def simulate_usage(request: Request, sim_request: SimulateRequest = None):  # Renamed parameter to avoid shadowing
    """Simulate usage events for all provided customers or the first 2 from the database."""
    conn = db_pool.getconn()
    try:
        cur = conn.cursor()

        # Use request body or default to None
        if sim_request is None:
            sim_request = SimulateRequest()
        
        # Get customers from input or database
        if sim_request.customers is None or not sim_request.customers:
            cur.execute("SELECT customer_id FROM customers ORDER BY customer_id LIMIT 2")
            customer_list = [row[0] for row in cur.fetchall()]
            if not customer_list:
                raise HTTPException(status_code=404, detail="No customers found in database")
            logger.info(f"Using default first 2 customers from database: {customer_list}")
        else:
            customer_list = sim_request.customers
            logger.info(f"Using provided customers: {customer_list}")
        
        # Validate customers exist
        cur.execute("SELECT customer_id FROM customers WHERE customer_id = ANY(%s)", (customer_list,))
        valid_customers = [row[0] for row in cur.fetchall()]
        invalid_customers = set(customer_list) - set(valid_customers)
        if invalid_customers:
            logger.warning(f"Invalid customers provided: {invalid_customers}")
        
        if not valid_customers:
            raise HTTPException(status_code=400, detail="No valid customers provided or found")

        # Simulate events for each customer
        total_events = 0
        while total_events < sim_request.num_events * len(valid_customers):
            for customer in valid_customers:
                action = random.choice(DEFAULT_ACTIONS)
                event = f"{customer}:{action}"
                redis_client.lpush("usage_queue", event)
                logger.info(f"Simulated event: {event}")
                total_events += 1
            await asyncio.sleep(sim_request.delay)
        
        return {"message": f"Simulated {total_events} usage events for customers: {valid_customers}"}
    
    except psycopg2.Error as e:
        logger.error(f"Database error during simulation: {str(e)}")
        conn.rollback()
        raise HTTPException(status_code=500, detail="Database error")
    except Exception as e:
        logger.error(f"Error during simulation: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        cur.close()
        db_pool.putconn(conn)

@app.on_event("shutdown")
async def shutdown_event():
    db_pool.closeall()
    logger.info("Database connection pool closed")