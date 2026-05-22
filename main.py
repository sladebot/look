"""Entry point — run with: python main.py"""
import uvicorn
from api.server import app, config

if __name__ == "__main__":
    print(f"Starting Look — Local Photo Library")
    print(f"UI:  http://{config.host}:{config.port}")
    print(f"API: http://{config.host}:{config.port}/api")
    print(f"DB:  {config.db_path}")
    uvicorn.run(app, host=config.host, port=config.port, log_level=config.log_level)
