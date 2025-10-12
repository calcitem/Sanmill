#!/usr/bin/env python3
"""
Sanmill Context Optimizer for LLM Interactions

This tool optimizes context injection for LLM interactions by:
1. Analyzing task requirements
2. Selecting relevant context based on semantic similarity
3. Managing token budgets efficiently
4. Providing intelligent context suggestions

Usage:
    python context_optimizer.py --task "add new widget" --target-file "lib/game_page/widgets/"
    python context_optimizer.py --analyze-dependencies --file "src/position.cpp"
    python context_optimizer.py --generate-context --task-type "bug_fix" --component "GameController"
"""

import json
import yaml
import argparse
import os
import re
import requests
from pathlib import Path
from typing import Dict, List, Tuple, Optional, Set
from dataclasses import dataclass
from datetime import datetime
import hashlib
import math

@dataclass
class ContextItem:
    """Represents a single context item with metadata."""
    path: str
    content: str
    relevance_score: float
    token_count: int
    category: str
    priority: str
    last_modified: datetime

@dataclass
class ContextPlan:
    """Represents a complete context injection plan."""
    items: List[ContextItem]
    total_tokens: int
    coverage_score: float
    task_type: str
    target_files: List[str]

class SanmillContextOptimizer:
    """Main context optimization engine for Sanmill project."""
    
    def __init__(self, project_root: str = ".", embedding_server_url: str = "http://localhost:8000"):
        self.project_root = Path(project_root)
        self.context_dir = self.project_root / ".sanmill" / "context"
        self.knowledge_dir = self.project_root / ".sanmill" / "knowledge"
        self.prompts_dir = self.project_root / ".sanmill" / "prompts"
        self.embedding_server_url = embedding_server_url
        
        # Load project metadata
        self.metadata = self._load_metadata()
        self.knowledge_graph = self._load_knowledge_graph()
        self.injection_rules = self._load_injection_rules()
        
        # Context categories and priorities
        self.priority_weights = {
            "P0": 1.0,  # Critical
            "P1": 0.8,  # High
            "P2": 0.6,  # Medium
            "P3": 0.4   # Low
        }
        
        # Token budget configuration
        self.max_context_tokens = 100000
        self.reserved_for_response = 20000
        self.available_tokens = self.max_context_tokens - self.reserved_for_response
        
        # Embedding server integration
        self.use_embeddings = True
        self.embedding_fallback = True
        
        # Context profiles (light, standard, deep)
        self.context_profiles = {
            "light": {
                "max_tokens": 40000,
                "include_examples": False,
                "summarize_long": True
            },
            "standard": {
                "max_tokens": 100000,
                "include_examples": True,
                "summarize_long": True
            },
            "deep": {
                "max_tokens": 180000,
                "include_examples": True,
                "summarize_long": False
            }
        }
    
    def _load_metadata(self) -> Dict:
        """Load project metadata."""
        metadata_file = self.context_dir / "PROJECT_METADATA.json"
        if metadata_file.exists():
            with open(metadata_file, 'r', encoding='utf-8') as f:
                return json.load(f)
        return {}
    
    def _load_knowledge_graph(self) -> Dict:
        """Load knowledge graph."""
        kg_file = self.knowledge_dir / "KNOWLEDGE_GRAPH.json"
        if kg_file.exists():
            with open(kg_file, 'r', encoding='utf-8') as f:
                return json.load(f)
        return {}
    
    def _load_injection_rules(self) -> Dict:
        """Load context injection rules."""
        rules_file = self.context_dir / "CONTEXT_INJECTION_RULES.md"
        # For now, return empty dict - in practice, would parse YAML from markdown
        return {}
    
    def analyze_task(self, task_description: str, target_file: Optional[str] = None) -> Dict:
        """Analyze task to determine type and requirements."""
        task_lower = task_description.lower()
        
        # Task type detection patterns
        task_patterns = {
            "add_widget": ["add.*widget", "create.*widget", "new.*widget", "implement.*widget"],
            "fix_bug": ["fix.*bug", "debug", "error", "crash", "issue"],
            "refactor": ["refactor", "improve", "optimize", "restructure"],
            "add_feature": ["add.*feature", "implement.*feature", "new.*feature"],
            "add_setting": ["add.*setting", "new.*setting", "setting.*option"],
            "engine_change": ["engine", "c\\+\\+", "search", "algorithm", "uci"],
            "ui_change": ["ui", "flutter", "widget", "screen", "page"],
            "test": ["test", "unit test", "widget test", "integration test"]
        }
        
        detected_type = "general"
        confidence = 0.0
        
        for task_type, patterns in task_patterns.items():
            for pattern in patterns:
                if re.search(pattern, task_lower):
                    detected_type = task_type
                    confidence = 0.8
                    break
            if confidence > 0:
                break
        
        # Extract keywords
        keywords = self._extract_keywords(task_description)
        
        # Determine affected components
        affected_components = self._identify_components(task_description, target_file)
        
        return {
            "task_type": detected_type,
            "confidence": confidence,
            "keywords": keywords,
            "affected_components": affected_components,
            "target_file": target_file
        }
    
    def _extract_keywords(self, text: str) -> List[str]:
        """Extract relevant keywords from task description."""
        # Simple keyword extraction - in practice, could use NLP
        technical_terms = [
            "GameController", "Position", "Engine", "GameBoard", "Database",
            "widget", "animation", "painter", "settings", "localization",
            "mill", "bitboard", "search", "uci", "flutter", "dart", "c++"
        ]
        
        keywords = []
        text_lower = text.lower()
        for term in technical_terms:
            if term.lower() in text_lower:
                keywords.append(term)
        
        return keywords
    
    def _identify_components(self, task_description: str, target_file: Optional[str]) -> List[str]:
        """Identify affected components based on task and target file."""
        components = []
        
        # Extract from knowledge graph
        if "entities" in self.knowledge_graph:
            for entity_name, entity_data in self.knowledge_graph["entities"].items():
                # Check if entity is mentioned in task
                if entity_name.lower() in task_description.lower():
                    components.append(entity_name)
                
                # Check if target file matches entity files
                if target_file and "file" in entity_data:
                    if target_file in entity_data["file"]:
                        components.append(entity_name)
                elif target_file and "files" in entity_data:
                    for file_path in entity_data["files"]:
                        if target_file in file_path:
                            components.append(entity_name)
        
        return list(set(components))
    
    def generate_context_plan(self, task_analysis: Dict, profile: str = "standard") -> ContextPlan:
        """Generate optimized context injection plan."""
        profile_cfg = self.context_profiles.get(profile, self.context_profiles["standard"])
        self.max_context_tokens = profile_cfg["max_tokens"]
        self.available_tokens = self.max_context_tokens - self.reserved_for_response

        context_items = []
        task_type = task_analysis["task_type"]
        keywords = task_analysis["keywords"]
        components = task_analysis["affected_components"]
        
        # 1. Add essential documentation (P0)
        essential_docs = [
            "AGENTS.md",
            "src/ui/flutter_app/docs/ARCHITECTURE.md",
            "src/ui/flutter_app/docs/COMPONENTS.md"
        ]
        
        for doc_path in essential_docs:
            if self._file_exists(doc_path):
                item = self._create_context_item(doc_path, "P0", "essential_docs")
                if item:
                    context_items.append(item)
        
        # 2. Add task-specific context (P0)
        task_specific = self._get_task_specific_context(task_type)
        for item_path in task_specific:
            if self._file_exists(item_path):
                item = self._create_context_item(item_path, "P0", "task_specific")
                if item:
                    context_items.append(item)
        
        # 3. Add component-specific context (P1)
        for component in components:
            component_context = self._get_component_context(component)
            for item_path in component_context:
                if self._file_exists(item_path):
                    item = self._create_context_item(item_path, "P1", "component_specific")
                    if item:
                        context_items.append(item)
        
        # 4. Add related examples (P2)
        if profile_cfg.get("include_examples", True):
            examples = self._get_related_examples(task_type, components)
            for item_path in examples:
                if self._file_exists(item_path):
                    item = self._create_context_item(item_path, "P2", "examples")
                    if item:
                        context_items.append(item)
        
        # 5. Calculate relevance scores
        for item in context_items:
            item.relevance_score = self._calculate_relevance(item, keywords, components)
        
        # 6. Summarize long items if profile requests
        if profile_cfg.get("summarize_long", True):
            context_items = self._summarize_long_items(context_items)

        # 7. Optimize token usage
        optimized_items = self._optimize_token_usage(context_items)
        
        # 8. Calculate coverage score
        coverage_score = self._calculate_coverage(optimized_items, task_analysis)
        
        return ContextPlan(
            items=optimized_items,
            total_tokens=sum(item.token_count for item in optimized_items),
            coverage_score=coverage_score,
            task_type=task_type,
            target_files=[task_analysis.get("target_file", "")]
        )

    def _summarize_long_items(self, items: List[ContextItem]) -> List[ContextItem]:
        """Summarize overly long items using embedding server summarizer."""
        summarized: List[ContextItem] = []
        for item in items:
            # Summarize markdown/docs only to preserve code fidelity
            should_summarize = item.path.endswith(('.md', '.markdown')) and item.token_count > 8000
            if not should_summarize:
                summarized.append(item)
                continue
            try:
                resp = requests.post(
                    f"{self.embedding_server_url}/summarize",
                    json={"text": item.content, "max_sentences": 10}, timeout=15
                )
                if resp.status_code == 200:
                    data = resp.json()
                    content = data.get('summary') or item.content
                    summarized.append(ContextItem(
                        path=item.path,
                        content=content,
                        relevance_score=item.relevance_score,
                        token_count=len(content)//4,
                        category=item.category,
                        priority=item.priority,
                        last_modified=item.last_modified
                    ))
                else:
                    summarized.append(item)
            except Exception:
                summarized.append(item)
        return summarized
    
    def _get_task_specific_context(self, task_type: str) -> List[str]:
        """Get context specific to task type."""
        task_context_map = {
            "add_widget": [
                "src/ui/flutter_app/docs/WORKFLOWS.md",
                "src/ui/flutter_app/docs/templates/widget_template.dart",
                "src/ui/flutter_app/docs/BEST_PRACTICES.md"
            ],
            "fix_bug": [
                "src/ui/flutter_app/docs/WORKFLOWS.md",
                "AGENTS.md"
            ],
            "add_setting": [
                "src/ui/flutter_app/docs/WORKFLOWS.md",
                "src/ui/flutter_app/lib/shared/database/database.dart",
                "src/ui/flutter_app/docs/STATE_MANAGEMENT.md"
            ],
            "engine_change": [
                "src/engine_controller.cpp",
                "src/ui/flutter_app/lib/game_page/services/engine/engine.dart",
                "AGENTS.md"
            ]
        }
        
        return task_context_map.get(task_type, [])
    
    def _get_component_context(self, component: str) -> List[str]:
        """Get context for specific component."""
        if "entities" not in self.knowledge_graph:
            return []
        
        entity = self.knowledge_graph["entities"].get(component, {})
        context_files = []
        
        # Add main files
        if "file" in entity:
            context_files.append(entity["file"])
        if "files" in entity:
            context_files.extend(entity["files"])
        
        # Add related documentation
        if "related_docs" in entity:
            context_files.extend(entity["related_docs"])
        
        # Add dependencies
        if "dependencies" in entity:
            for dep in entity["dependencies"]:
                dep_entity = self.knowledge_graph["entities"].get(dep, {})
                if "file" in dep_entity:
                    context_files.append(dep_entity["file"])
        
        return context_files
    
    def _search_with_embeddings(self, query: str, max_results: int = 10) -> List[str]:
        """Search using vector embeddings server."""
        if not self.use_embeddings:
            return []
        
        try:
            response = requests.post(
                f"{self.embedding_server_url}/search",
                json={
                    "query": query,
                    "max_results": max_results,
                    "similarity_threshold": 0.4,
                    "filter_categories": None
                },
                timeout=10
            )
            
            if response.status_code == 200:
                results = response.json()
                return [result["path"] for result in results]
            else:
                print(f"Embedding search failed with status {response.status_code}")
                return []
                
        except requests.RequestException as e:
            if self.embedding_fallback:
                print(f"Embedding server unavailable, using fallback: {e}")
                return []
            else:
                raise
    
    def _get_related_examples(self, task_type: str, components: List[str]) -> List[str]:
        """Get related examples and templates using embeddings + fallback."""
        examples = []
        
        # Try semantic search first
        if self.use_embeddings:
            query = f"{task_type} {' '.join(components)} examples"
            embedding_results = self._search_with_embeddings(query, max_results=5)
            
            # Filter for actual examples/templates
            for path in embedding_results:
                if any(keyword in path.lower() for keyword in ["example", "template", "docs/"]):
                    examples.append(path)
        
        # Add templates based on task type (fallback/supplement)
        if task_type in ["add_widget", "ui_change"]:
            examples.append("src/ui/flutter_app/docs/templates/widget_template.dart")
        
        if task_type in ["add_setting"]:
            examples.append("src/ui/flutter_app/docs/templates/service_template.dart")
        
        # Add examples directory
        examples_dir = self.project_root / "src/ui/flutter_app/docs/examples"
        if examples_dir.exists():
            examples.append("src/ui/flutter_app/docs/examples/README.md")
        
        return list(set(examples))  # Remove duplicates
    
    def _file_exists(self, file_path: str) -> bool:
        """Check if file exists in project."""
        full_path = self.project_root / file_path
        return full_path.exists()
    
    def _create_context_item(self, file_path: str, priority: str, category: str) -> Optional[ContextItem]:
        """Create a context item from file path."""
        full_path = self.project_root / file_path
        
        if not full_path.exists():
            return None
        
        try:
            with open(full_path, 'r', encoding='utf-8') as f:
                content = f.read()
            
            # Estimate token count (rough approximation: 1 token ≈ 4 characters)
            token_count = len(content) // 4
            
            # Get file modification time
            last_modified = datetime.fromtimestamp(full_path.stat().st_mtime)
            
            return ContextItem(
                path=file_path,
                content=content,
                relevance_score=0.0,  # Will be calculated later
                token_count=token_count,
                category=category,
                priority=priority,
                last_modified=last_modified
            )
        except Exception as e:
            print(f"Error reading file {file_path}: {e}")
            return None
    
    def _calculate_relevance(self, item: ContextItem, keywords: List[str], components: List[str]) -> float:
        """Calculate relevance score for context item."""
        score = 0.0
        content_lower = item.content.lower()
        
        # Keyword matching (30% weight)
        keyword_matches = sum(1 for keyword in keywords if keyword.lower() in content_lower)
        if keywords:
            score += 0.3 * (keyword_matches / len(keywords))
        
        # Component matching (30% weight)
        component_matches = sum(1 for comp in components if comp.lower() in content_lower)
        if components:
            score += 0.3 * (component_matches / len(components))
        
        # Priority weight (20% weight)
        priority_weight = self.priority_weights.get(item.priority, 0.5)
        score += 0.2 * priority_weight
        
        # Freshness (10% weight) - more recent files get higher scores
        days_old = (datetime.now() - item.last_modified).days
        freshness = max(0, 1 - days_old / 365)  # Decay over a year
        score += 0.1 * freshness
        
        # File importance from metadata (10% weight)
        importance = self.metadata.get("file_importance_weights", {}).get(item.path, 0.5)
        score += 0.1 * importance
        
        return min(1.0, score)  # Cap at 1.0
    
    def _optimize_token_usage(self, context_items: List[ContextItem]) -> List[ContextItem]:
        """Optimize context items to fit within token budget."""
        # Sort by relevance score (descending) and priority
        sorted_items = sorted(
            context_items,
            key=lambda x: (self.priority_weights.get(x.priority, 0.5), x.relevance_score),
            reverse=True
        )
        
        selected_items = []
        total_tokens = 0
        
        # First pass: Add all P0 items
        for item in sorted_items:
            if item.priority == "P0":
                if total_tokens + item.token_count <= self.available_tokens:
                    selected_items.append(item)
                    total_tokens += item.token_count
                else:
                    # Truncate content if necessary for P0 items
                    remaining_tokens = self.available_tokens - total_tokens
                    if remaining_tokens > 1000:  # Minimum useful size
                        truncated_item = self._truncate_item(item, remaining_tokens)
                        selected_items.append(truncated_item)
                        total_tokens += truncated_item.token_count
                        break
        
        # Second pass: Add other items by relevance
        for item in sorted_items:
            if item.priority != "P0" and total_tokens + item.token_count <= self.available_tokens:
                selected_items.append(item)
                total_tokens += item.token_count
        
        return selected_items
    
    def _truncate_item(self, item: ContextItem, max_tokens: int) -> ContextItem:
        """Truncate content to fit token budget."""
        max_chars = max_tokens * 4  # Rough approximation
        
        if len(item.content) <= max_chars:
            return item
        
        # Try to truncate at a reasonable boundary (paragraph, section)
        truncated_content = item.content[:max_chars]
        
        # Find last paragraph break
        last_para = truncated_content.rfind('\n\n')
        if last_para > max_chars * 0.7:  # If we don't lose too much
            truncated_content = truncated_content[:last_para]
        
        truncated_content += "\n\n[... truncated for token limit ...]"
        
        return ContextItem(
            path=item.path,
            content=truncated_content,
            relevance_score=item.relevance_score,
            token_count=len(truncated_content) // 4,
            category=item.category,
            priority=item.priority,
            last_modified=item.last_modified
        )
    
    def _calculate_coverage(self, items: List[ContextItem], task_analysis: Dict) -> float:
        """Calculate how well the context covers the task requirements."""
        required_categories = ["essential_docs", "task_specific"]
        covered_categories = set(item.category for item in items)
        
        category_coverage = len(covered_categories.intersection(required_categories)) / len(required_categories)
        
        # Check if we have component-specific context for affected components
        component_coverage = 0.0
        if task_analysis["affected_components"]:
            component_items = [item for item in items if item.category == "component_specific"]
            component_coverage = min(1.0, len(component_items) / len(task_analysis["affected_components"]))
        else:
            component_coverage = 1.0  # No components needed
        
        # Overall coverage is weighted average
        return 0.6 * category_coverage + 0.4 * component_coverage
    
    def generate_context_prompt(self, context_plan: ContextPlan) -> str:
        """Generate formatted context prompt for LLM."""
        prompt_parts = []
        
        # Header
        prompt_parts.append(f"# Context for: {context_plan.task_type.replace('_', ' ').title()}")
        prompt_parts.append("")
        prompt_parts.append(f"**Context Coverage**: {context_plan.coverage_score:.2%}")
        prompt_parts.append(f"**Total Tokens**: {context_plan.total_tokens:,}")
        prompt_parts.append("")
        
        # Group items by category and priority
        categories = {}
        for item in context_plan.items:
            key = f"{item.priority}_{item.category}"
            if key not in categories:
                categories[key] = []
            categories[key].append(item)
        
        # Sort categories by priority
        priority_order = ["P0", "P1", "P2", "P3"]
        sorted_categories = sorted(categories.items(), 
                                 key=lambda x: (priority_order.index(x[0].split('_')[0]), x[0]))
        
        # Add content by category
        for category_key, items in sorted_categories:
            priority, category = category_key.split('_', 1)
            category_title = category.replace('_', ' ').title()
            
            prompt_parts.append(f"## {category_title} ({priority})")
            prompt_parts.append("")
            
            for item in items:
                prompt_parts.append(f"### {item.path}")
                prompt_parts.append(f"*Relevance: {item.relevance_score:.2%} | Tokens: {item.token_count:,}*")
                prompt_parts.append("")
                prompt_parts.append("```")
                prompt_parts.append(item.content)
                prompt_parts.append("```")
                prompt_parts.append("")
        
        return "\n".join(prompt_parts)
    
    def analyze_dependencies(self, file_path: str) -> Dict:
        """Analyze file dependencies for context injection."""
        full_path = self.project_root / file_path
        
        if not full_path.exists():
            return {"error": f"File not found: {file_path}"}
        
        dependencies = {
            "direct_imports": [],
            "related_components": [],
            "suggested_context": []
        }
        
        try:
            with open(full_path, 'r', encoding='utf-8') as f:
                content = f.read()
            
            # Extract imports (simplified)
            if file_path.endswith('.dart'):
                import_pattern = r"import\s+['\"]([^'\"]+)['\"]"
                imports = re.findall(import_pattern, content)
                dependencies["direct_imports"] = imports
            elif file_path.endswith(('.cpp', '.h')):
                include_pattern = r"#include\s+[<\"]([^>\"]+)[>\"]"
                includes = re.findall(include_pattern, content)
                dependencies["direct_imports"] = includes
            
            # Find related components from knowledge graph
            for entity_name, entity_data in self.knowledge_graph.get("entities", {}).items():
                entity_files = []
                if "file" in entity_data:
                    entity_files.append(entity_data["file"])
                if "files" in entity_data:
                    entity_files.extend(entity_data["files"])
                
                if file_path in entity_files:
                    dependencies["related_components"].append(entity_name)
                    
                    # Add dependencies of this component
                    if "dependencies" in entity_data:
                        dependencies["suggested_context"].extend(entity_data["dependencies"])
                    
                    # Add related documentation
                    if "related_docs" in entity_data:
                        dependencies["suggested_context"].extend(entity_data["related_docs"])
        
        except Exception as e:
            dependencies["error"] = str(e)
        
        return dependencies

def main():
    parser = argparse.ArgumentParser(description="Sanmill Context Optimizer")
    parser.add_argument("--task", help="Task description")
    parser.add_argument("--target-file", help="Target file path")
    parser.add_argument("--task-type", help="Specific task type")
    parser.add_argument("--component", help="Target component name")
    parser.add_argument("--analyze-dependencies", action="store_true", help="Analyze file dependencies")
    parser.add_argument("--file", help="File to analyze")
    parser.add_argument("--generate-context", action="store_true", help="Generate context plan")
    parser.add_argument("--output", help="Output file for context")
    parser.add_argument("--max-tokens", type=int, default=100000, help="Maximum context tokens")
    
    args = parser.parse_args()
    
    optimizer = SanmillContextOptimizer()
    optimizer.max_context_tokens = args.max_tokens
    optimizer.available_tokens = args.max_tokens - optimizer.reserved_for_response
    
    if args.analyze_dependencies and args.file:
        result = optimizer.analyze_dependencies(args.file)
        print(json.dumps(result, indent=2))
    
    elif args.generate_context or args.task:
        if args.task:
            task_analysis = optimizer.analyze_task(args.task, args.target_file)
        else:
            # Create task analysis from other parameters
            task_analysis = {
                "task_type": args.task_type or "general",
                "confidence": 0.8,
                "keywords": [args.component] if args.component else [],
                "affected_components": [args.component] if args.component else [],
                "target_file": args.target_file
            }
        
        print("Task Analysis:")
        print(json.dumps(task_analysis, indent=2))
        print()
        
        context_plan = optimizer.generate_context_plan(task_analysis)
        
        print(f"Context Plan Summary:")
        print(f"- Items: {len(context_plan.items)}")
        print(f"- Total Tokens: {context_plan.total_tokens:,}")
        print(f"- Coverage Score: {context_plan.coverage_score:.2%}")
        print()
        
        # Generate and display context prompt
        context_prompt = optimizer.generate_context_prompt(context_plan)
        
        if args.output:
            with open(args.output, 'w', encoding='utf-8') as f:
                f.write(context_prompt)
            print(f"Context saved to: {args.output}")
        else:
            print("Generated Context:")
            print("=" * 80)
            print(context_prompt)
    
    else:
        parser.print_help()

if __name__ == "__main__":
    main()
