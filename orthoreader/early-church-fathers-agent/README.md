# Early Church Fathers PDF Agent

## Project Overview
AI-powered agent to find, download, clean, and organize early church fathers' texts into PDFs for the OrthoReader iOS app.

## Project Structure
```
early-church-fathers-agent/
├── src/
│   ├── agents/
│   │   ├── search_agent.py
│   │   ├── download_agent.py
│   │   ├── cleaning_agent.py
│   │   └── pdf_agent.py
│   ├── utils/
│   │   ├── text_processing.py
│   │   └── file_utils.py
│   └── data/
│       └── sources.json
├── output/
│   └── LibraryPDFs/
├── tests/
├── requirements.txt
└── README.md
```

## Setup
1. Create virtual environment: `python3 -m venv venv`
2. Activate: `source venv/bin/activate`
3. Install dependencies: `pip install -r requirements.txt`

## Usage
```python
from src.agents.search_agent import SearchAgent
from src.agents.download_agent import DownloadAgent

# Search for works
search_agent = SearchAgent()
works = search_agent.find_works_by_author("St John Chrysostom")

# Download and process
download_agent = DownloadAgent()
for work in works:
    download_agent.process_work(work)
```

## Sources
- CCEL.org (Christian Classics Ethereal Library)
- NewAdvent.org (Catholic Encyclopedia)
- EarlyChristianWritings.com
- Archive.org

## Status: IN DEVELOPMENT 