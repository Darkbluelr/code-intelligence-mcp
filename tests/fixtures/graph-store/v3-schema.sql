-- v3 schema fixture for migration testing
-- This represents the actual v3 database schema that needs migration to v4

PRAGMA foreign_keys = OFF;

-- Schema version table (v3)
CREATE TABLE IF NOT EXISTS schema_version (
    id INTEGER PRIMARY KEY CHECK (id = 1),
    version INTEGER NOT NULL DEFAULT 3,
    created_at TEXT DEFAULT (datetime('now')),
    updated_at TEXT DEFAULT (datetime('now'))
);
INSERT OR REPLACE INTO schema_version (id, version) VALUES (1, 3);

-- Nodes table (v3 structure - missing some v4 columns)
CREATE TABLE IF NOT EXISTS nodes (
    id TEXT PRIMARY KEY,
    symbol TEXT NOT NULL,
    kind TEXT NOT NULL,
    file TEXT NOT NULL,
    line INTEGER,
    col INTEGER,
    created_at TEXT DEFAULT (datetime('now'))
    -- Note: v4 adds 'doc', 'signature', 'updated_at' columns
);

-- Edges table (v3 structure)
CREATE TABLE IF NOT EXISTS edges (
    id TEXT PRIMARY KEY,
    source_id TEXT NOT NULL,
    target_id TEXT NOT NULL,
    edge_type TEXT NOT NULL,
    created_at TEXT DEFAULT (datetime('now')),
    FOREIGN KEY (source_id) REFERENCES nodes(id),
    FOREIGN KEY (target_id) REFERENCES nodes(id)
    -- Note: v4 adds 'weight', 'metadata' columns
);

-- Indexes (v3)
CREATE INDEX IF NOT EXISTS idx_nodes_symbol ON nodes(symbol);
CREATE INDEX IF NOT EXISTS idx_nodes_file ON nodes(file);
CREATE INDEX IF NOT EXISTS idx_edges_source ON edges(source_id);
CREATE INDEX IF NOT EXISTS idx_edges_target ON edges(target_id);
CREATE INDEX IF NOT EXISTS idx_edges_type ON edges(edge_type);

-- Sample data for migration verification
INSERT INTO nodes (id, symbol, kind, file, line, col) VALUES
    ('node-1', 'UserService', 'class', 'src/user.ts', 10, 1),
    ('node-2', 'getUser', 'function', 'src/user.ts', 25, 3),
    ('node-3', 'AuthService', 'class', 'src/auth.ts', 5, 1),
    ('node-4', 'login', 'function', 'src/auth.ts', 15, 3);

INSERT INTO edges (id, source_id, target_id, edge_type) VALUES
    ('edge-1', 'node-2', 'node-1', 'CONTAINS'),
    ('edge-2', 'node-4', 'node-3', 'CONTAINS'),
    ('edge-3', 'node-4', 'node-2', 'CALLS');

PRAGMA foreign_keys = ON;
