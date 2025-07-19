"""
Search Agent for finding early church fathers' works
"""

import requests
from bs4 import BeautifulSoup
import json
from typing import List, Dict
import time

class SearchAgent:
    def __init__(self):
        self.sources = {
            "ccel": {
                "base_url": "https://www.ccel.org",
                "search_url": "https://www.ccel.org/search",
                "authors": {
                    "St John Chrysostom": "/ccel/chrysostom",
                    "St Augustine": "/ccel/augustine",
                    "St Basil": "/ccel/basil",
                    "St Gregory": "/ccel/gregory"
                }
            },
            "newadvent": {
                "base_url": "https://www.newadvent.org",
                "search_url": "https://www.newadvent.org/fathers"
            }
        }
        self.session = requests.Session()
        self.session.headers.update({
            'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36'
        })
    
    def find_works_by_author(self, author_name: str) -> List[Dict]:
        """Find all works by a specific author"""
        works = []
        
        # Search CCEL
        if author_name in self.sources["ccel"]["authors"]:
            ccel_works = self._search_ccel(author_name)
            works.extend(ccel_works)
        
        # Search New Advent
        newadvent_works = self._search_newadvent(author_name)
        works.extend(newadvent_works)
        
        return works
    
    def _search_ccel(self, author_name: str) -> List[Dict]:
        """Search CCEL for author's works"""
        works = []
        author_path = self.sources["ccel"]["authors"].get(author_name)
        
        if not author_path:
            return works
        
        try:
            url = f"{self.sources['ccel']['base_url']}{author_path}"
            response = self.session.get(url)
            soup = BeautifulSoup(response.content, 'html.parser')
            
            # Find links to individual works
            links = soup.find_all('a', href=True)
            for link in links:
                href = link.get('href')
                if href and '/ccel/' in href and href != author_path:
                    title = link.get_text().strip()
                    if title:
                        works.append({
                            'title': title,
                            'url': f"{self.sources['ccel']['base_url']}{href}",
                            'source': 'ccel',
                            'author': author_name
                        })
            
            time.sleep(1)  # Be respectful to the server
            
        except Exception as e:
            print(f"Error searching CCEL for {author_name}: {e}")
        
        return works
    
    def _search_newadvent(self, author_name: str) -> List[Dict]:
        """Search New Advent for author's works"""
        works = []
        
        try:
            url = self.sources["newadvent"]["search_url"]
            response = self.session.get(url)
            soup = BeautifulSoup(response.content, 'html.parser')
            
            # Search for author name in the page
            # This is a simplified search - you might need to refine this
            links = soup.find_all('a', href=True)
            for link in links:
                text = link.get_text().lower()
                if author_name.lower() in text:
                    href = link.get('href')
                    if href and '/fathers/' in href:
                        works.append({
                            'title': link.get_text().strip(),
                            'url': f"{self.sources['newadvent']['base_url']}{href}",
                            'source': 'newadvent',
                            'author': author_name
                        })
            
            time.sleep(1)
            
        except Exception as e:
            print(f"Error searching New Advent for {author_name}: {e}")
        
        return works
    
    def validate_source_quality(self, url: str) -> Dict:
        """Validate the quality of a source"""
        try:
            response = self.session.get(url)
            soup = BeautifulSoup(response.content, 'html.parser')
            
            # Check for common quality indicators
            text_content = soup.get_text()
            word_count = len(text_content.split())
            
            quality_score = 0
            issues = []
            
            # Check text length
            if word_count < 100:
                issues.append("Very short text")
                quality_score -= 2
            elif word_count > 10000:
                quality_score += 1
            
            # Check for common problems
            if "page not found" in text_content.lower():
                issues.append("Page not found")
                quality_score -= 3
            
            if "error" in text_content.lower():
                issues.append("Error page")
                quality_score -= 2
            
            return {
                'quality_score': quality_score,
                'word_count': word_count,
                'issues': issues,
                'is_valid': quality_score >= 0
            }
            
        except Exception as e:
            return {
                'quality_score': -1,
                'word_count': 0,
                'issues': [f"Error accessing URL: {e}"],
                'is_valid': False
            }

if __name__ == "__main__":
    # Test the search agent
    agent = SearchAgent()
    works = agent.find_works_by_author("St John Chrysostom")
    print(f"Found {len(works)} works by St John Chrysostom")
    for work in works[:5]:  # Show first 5
        print(f"- {work['title']} ({work['source']})") 