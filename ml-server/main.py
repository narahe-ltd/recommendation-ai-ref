from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import redis
import psycopg2
from sentence_transformers import SentenceTransformer
import numpy as np
import logging
import time
from typing import List, Dict, Optional
import os
from dotenv import load_dotenv
import random
import asyncio
import aiohttp  # For async HTTP requests to OpenAI API
from fastapi.middleware.cors import CORSMiddleware

# Load environment variables
load_dotenv()

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI()
app.add_middleware(CORSMiddleware, allow_origins=os.getenv("CORS_ALLOW_ORIGINS", "*").split(","), allow_methods=["*"], allow_headers=["*"])

# Pydantic model for simulation request
class SimulateRequest(BaseModel):
    customers: Optional[List[str]] = None
    num_events: int = 10
    delay: float = 2.0

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

# Database connection
conn = psycopg2.connect(
    dbname=os.getenv('POSTGRES_DB', 'bank_recommendations'),
    user=os.getenv('POSTGRES_USER', 'bank_user'),
    password=os.getenv('POSTGRES_PASSWORD', 'secure_password_123'),
    host=os.getenv('POSTGRES_HOST', 'postgres')
)

# Redis connection
redis_client = redis.Redis.from_url(os.getenv('REDIS_URL', 'redis://redis:6379'))

# OpenAI API configuration
OPENAI_API_KEY = os.getenv('OPENAI_API_KEY')
OPENAI_API_URL = os.getenv('OPENAI_API_URL', 'https://api.openai.com/v1/chat/completions')

def generate_embedding(text: str) -> List[float]:
    """Generate embedding from text, handling empty inputs."""
    if not text.strip():
        logger.warning("Empty text provided for embedding, using default empty string")
        text = ""
    return model.encode(text).tolist()

async def generate_recommendation_explanation(customer_data: tuple, products: List[tuple]) -> str:
    """Generate a natural language explanation using ChatGPT."""
    transaction_history, preferences = customer_data
    product_str = "\n".join([f"- {p[0]}: {p[1]}" for p in products])
    prompt = (
        f"Customer Profile:\n"
        f"Transaction History: {transaction_history}\n"
        f"Preferences: {preferences}\n\n"
        f"Recommended Products:\n{product_str}\n\n"
        f"Explain in a concise, friendly tone why these products are suitable for this customer."
    )
    
    try:
        async with aiohttp.ClientSession() as session:
            async with session.post(
                OPENAI_API_URL,
                headers={
                    "Authorization": f"Bearer {OPENAI_API_KEY}",
                    "Content-Type": "application/json"
                },
                json={
                    "model": "gpt-3.5-turbo",  # Or "gpt-4" if you have access
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
                    return result["choices"][0]["message"]["content"].strip()
                else:
                    logger.error(f"OpenAI API error: {result}")
                    return "Sorry, I couldn't generate a detailed explanation at this time."
    except Exception as e:
        logger.error(f"Error generating explanation with ChatGPT: {str(e)}")
        return "Sorry, I couldn't generate a detailed explanation at this time."

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

@app.post("/encode")
async def encode_text(texts: List[str]) -> Dict[str, List[List[float]]]:
    try:
        embeddings = model.encode(texts)
        return {"embeddings": embeddings.tolist()}
    except Exception as e:
        logger.error(f"Error during text encoding: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/recommendations/{customer_id}")
async def get_recommendations(customer_id: str):
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
            embedding = generate_embedding(text)
            logger.info(f"Generated new embedding for customer {customer_id}")
            cur.execute("""
                UPDATE customers 
                SET embedding = %s::vector 
                WHERE customer_id = %s
            """, (embedding, customer_id))
            conn.commit()
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
        if 'cur' in locals():
            cur.close()

@app.on_event("startup")
async def startup_event():
    """Initialize product embeddings on startup."""
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
        if 'cur' in locals():
            cur.close()

@app.post("/simulate_usage")
async def simulate_usage(request: SimulateRequest = None):
    """Simulate usage events for all provided customers or the first 2 from the database."""
    try:
        cur = conn.cursor()
        
        # Use request body or default to None
        if request is None:
            sim_request = SimulateRequest()
        else:
            sim_request = request
        
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
        while total_events < 10 * len(valid_customers):
            for customer in valid_customers:
                action = random.choice(DEFAULT_ACTIONS)
                event = f"{customer}:{action}"
                redis_client.lpush("usage_queue", event)
                logger.info(f"Simulated event: {event}")
                total_events += 1
            await asyncio.sleep(sim_request.delay)   # 2 seconds delay after one cycle of customers
        
        return {"message": f"Simulated {sim_request.num_events} usage events for customers: {valid_customers}"}
    
    except psycopg2.Error as e:
        logger.error(f"Database error during simulation: {str(e)}")
        raise HTTPException(status_code=500, detail="Database error")
    except Exception as e:
        logger.error(f"Error during simulation: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        if 'cur' in locals():
            cur.close()

@app.on_event("shutdown")
async def shutdown_event():
    conn.close()
    logger.info("Database connection closed")