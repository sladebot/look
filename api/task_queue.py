"""Async Task Queue — background processing for long-running operations."""
import threading
import uuid
import time
from datetime import datetime
from typing import Optional, Dict, Any
from enum import Enum


class TaskStatus(str, Enum):
    PENDING = "pending"
    RUNNING = "running"
    COMPLETED = "completed"
    FAILED = "failed"
    CANCELLED = "cancelled"


class Task:
    """Represents a single background task."""

    def __init__(self, task_id: str, task_type: str, params: dict):
        self.task_id = task_id
        self.task_type = task_type
        self.params = params
        self.status = TaskStatus.PENDING
        self.result: Optional[Dict[str, Any]] = None
        self.error: Optional[str] = None
        self.progress: Dict[str, Any] = {}
        self.created_at = datetime.now().isoformat()
        self.completed_at: Optional[str] = None
        self._cancel_requested = False

    def to_dict(self) -> dict:
        result = {
            "task_id": self.task_id,
            "task_type": self.task_type,
            "status": self.status.value,
            "params": self.params,
            "result": self.result,
            "error": self.error,
            "progress": self.progress,
            "created_at": self.created_at,
        }
        if self.completed_at:
            result["completed_at"] = self.completed_at
        return result


class TaskQueue:
    """Thread-safe task queue with background workers.

    Usage:
        queue = TaskQueue(db)
        task_id = queue.submit_task("dedup_scan", {"tolerance": 20})
        # Poll status: task = queue.get_task(task_id)
        # Check task.status, task.result, task.error
    """

    def __init__(self, db, dedup_engine=None, import_handler=None, _max_tasks=1000):
        self.db = db
        self.dedup_engine = dedup_engine
        self.import_handler = import_handler
        self._tasks: Dict[str, Task] = {}
        self._lock = threading.Lock()
        self._workers: Dict[str, threading.Thread] = {}
        # Keep only last _max_tasks tasks in memory (older ones are cleaned up)
        self._max_tasks = _max_tasks

    def submit_task(self, task_type: str, params: Optional[dict] = None) -> str:
        """Submit a new task and start a background worker. Returns task_id."""
        if params is None:
            params = {}
        task_id = str(uuid.uuid4())[:12]
        task = Task(task_id, task_type, params)

        with self._lock:
            # Prune old completed tasks if we've exceeded the limit
            if len(self._tasks) >= self._max_tasks:
                self._prune_old_tasks()
            self._tasks[task_id] = task

        # Start background worker thread
        worker = threading.Thread(
            target=self._worker, args=(task_type, task_id, params),
            daemon=True, name=f"task-{task_id}"
        )
        worker.start()
        self._workers[task_id] = worker

        return task_id

    def get_task(self, task_id: str) -> Optional[dict]:
        """Get task status and result (or error). Returns None if not found."""
        with self._lock:
            task = self._tasks.get(task_id)
            if task is None:
                return None
            return task.to_dict()

    def cancel_task(self, task_id: str) -> bool:
        """Cancel a running/pending task. Returns True if task was found and cancelled."""
        with self._lock:
            task = self._tasks.get(task_id)
            if task is None:
                return False
            if task.status in (TaskStatus.COMPLETED, TaskStatus.CANCELLED, TaskStatus.FAILED):
                return False
            task._cancel_requested = True
            task.status = TaskStatus.CANCELLED
            task.completed_at = datetime.now().isoformat()
            return True

    def list_tasks(self, limit: int = 50, offset: int = 0) -> list:
        """List all tasks, newest first."""
        with self._lock:
            tasks = sorted(
                self._tasks.values(),
                key=lambda t: t.created_at,
                reverse=True
            )
            return [t.to_dict() for t in tasks[offset:offset + limit]]

    def find_active_task(self, task_type: str, params: Optional[dict] = None) -> Optional[dict]:
        """Return the newest pending/running task for a type and optional exact params."""
        with self._lock:
            tasks = sorted(
                self._tasks.values(),
                key=lambda t: t.created_at,
                reverse=True,
            )
            for task in tasks:
                if task.task_type != task_type:
                    continue
                if task.status not in (TaskStatus.PENDING, TaskStatus.RUNNING):
                    continue
                if params is not None and task.params != params:
                    continue
                return task.to_dict()
        return None

    def _prune_old_tasks(self):
        """Remove old completed/failed/cancelled tasks, keeping the most recent."""
        if len(self._tasks) <= self._max_tasks:
            return
        # Sort by created_at, remove oldest completed tasks
        sorted_tasks = sorted(
            self._tasks.items(),
            key=lambda kv: kv[1].created_at
        )
        # Remove oldest 100 tasks if we're over the limit
        to_remove = sorted_tasks[:max(0, len(self._tasks) - self._max_tasks)]
        for task_id, _ in to_remove:
            del self._tasks[task_id]

    def _worker(self, task_type: str, task_id: str, params: dict):
        """Background worker that executes the task."""
        with self._lock:
            task = self._tasks.get(task_id)
            if task is None:
                return
            task.status = TaskStatus.RUNNING

        try:
            if task_type == "dedup_scan":
                result = self._execute_dedup_scan(task, params)
            elif task_type == "import":
                result = self._execute_import(task, params)
            elif task_type == "tag_auto":
                result = self._execute_auto_tag(task, params)
            else:
                result = {"error": f"Unknown task type: {task_type}"}
                task.status = TaskStatus.FAILED
                task.error = f"Unknown task type: {task_type}"

            with self._lock:
                task.result = result
                task.status = TaskStatus.COMPLETED if task.result.get("error") is None else TaskStatus.FAILED
                task.completed_at = datetime.now().isoformat()
        except Exception as e:
            with self._lock:
                task.status = TaskStatus.FAILED
                task.error = str(e)
                task.completed_at = datetime.now().isoformat()
        finally:
            with self._lock:
                self._workers.pop(task_id, None)

    def _execute_dedup_scan(self, task: Task, params: dict) -> dict:
        """Execute a deduplication scan asynchronously."""
        if self.dedup_engine is None:
            return {"error": "Deduplication engine not configured"}

        tolerance = params.get("tolerance", 20)

        # Scan for duplicates (this may take a while for large libraries)
        total_photos = self.db.get_photo_count()
        if total_photos == 0:
            return {"groups": [], "total_groups": 0, "total_photos_scanned": 0}

        groups = self.dedup_engine.scan()

        return {
            "groups": groups,
            "total_groups": len(groups),
            "total_photos_scanned": len(self.dedup_engine.duplicate_groups) if hasattr(self.dedup_engine, 'duplicate_groups') else 0,
        }

    def _execute_import(self, task: Task, params: dict) -> dict:
        """Execute an import operation asynchronously."""
        if self.import_handler is None:
            return {"error": "Import handler not configured"}
        return self.import_handler(task, params)

    def _execute_auto_tag(self, task: Task, params: dict) -> dict:
        """Execute auto-tagging for a photo."""
        # Placeholder — actual auto-tagging is synchronous per-photo
        return {"status": "auto-tag requested", "params": params}
