from fastapi import FastAPI, HTTPException
import redis
import psycopg2
from sentence_transformers import SentenceTransformer
import numpy as np
import logging
import time
from typing import List, Dict
import os

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI()

# Initialize model with retry mechanism
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

redis_client = redis.Redis.from_url("redis://redis:6379")

# Database connection
conn = psycopg2.connect(
    dbname="bank_recommendations",
    user="bank_user",
    password="secure_password_123",
    host="postgres"
)

def generate_embedding(text: str) -> List[float]:
    """Generate embedding from text, handling empty inputs."""
    if not text.strip():
        logger.warning("Empty text provided for embedding, using default empty string")
        text = ""
    return model.encode(text).tolist()

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
        
        # Get similar products/services
        cur.execute("""
            SELECT product_id, description 
            FROM products 
            ORDER BY embedding <=> %s 
            LIMIT 5
        """, (embedding,))
        recommendations = cur.fetchall()
        logger.info(f"Found {len(recommendations)} recommendations for {customer_id}")
        
        # Cache results
        redis_client.setex(f"recs:{customer_id}", 3600, str(recommendations))
        logger.info(f"Recommendations cached for customer {customer_id}")
        
        return {"customer_id": customer_id, "recommendations": recommendations}
    
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

# Ensure connection cleanup
@app.on_event("shutdown")
async def shutdown_event():
    conn.close()
    logger.info("Database connection closed")