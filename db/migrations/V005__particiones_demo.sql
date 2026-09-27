-- =============================================================================
-- V005__particiones_demo.sql — Particiones mensuales oct-2025 a ago-2026
-- La ventana demo es 2025-10-01 a 2026-09-30 (12 meses). El master v12 solo trae
-- y2026m09 e y2026m10; aquí se crean las 10 restantes (y2026m09 ya existe).
-- =============================================================================

CREATE TABLE IF NOT EXISTS core.transacciones_y2025m10 PARTITION OF core.transacciones
    FOR VALUES FROM ('2025-10-01 00:00:00+00') TO ('2025-11-01 00:00:00+00');
CREATE TABLE IF NOT EXISTS core.transacciones_y2025m11 PARTITION OF core.transacciones
    FOR VALUES FROM ('2025-11-01 00:00:00+00') TO ('2025-12-01 00:00:00+00');
CREATE TABLE IF NOT EXISTS core.transacciones_y2025m12 PARTITION OF core.transacciones
    FOR VALUES FROM ('2025-12-01 00:00:00+00') TO ('2026-01-01 00:00:00+00');
CREATE TABLE IF NOT EXISTS core.transacciones_y2026m01 PARTITION OF core.transacciones
    FOR VALUES FROM ('2026-01-01 00:00:00+00') TO ('2026-02-01 00:00:00+00');
CREATE TABLE IF NOT EXISTS core.transacciones_y2026m02 PARTITION OF core.transacciones
    FOR VALUES FROM ('2026-02-01 00:00:00+00') TO ('2026-03-01 00:00:00+00');
CREATE TABLE IF NOT EXISTS core.transacciones_y2026m03 PARTITION OF core.transacciones
    FOR VALUES FROM ('2026-03-01 00:00:00+00') TO ('2026-04-01 00:00:00+00');
CREATE TABLE IF NOT EXISTS core.transacciones_y2026m04 PARTITION OF core.transacciones
    FOR VALUES FROM ('2026-04-01 00:00:00+00') TO ('2026-05-01 00:00:00+00');
CREATE TABLE IF NOT EXISTS core.transacciones_y2026m05 PARTITION OF core.transacciones
    FOR VALUES FROM ('2026-05-01 00:00:00+00') TO ('2026-06-01 00:00:00+00');
CREATE TABLE IF NOT EXISTS core.transacciones_y2026m06 PARTITION OF core.transacciones
    FOR VALUES FROM ('2026-06-01 00:00:00+00') TO ('2026-07-01 00:00:00+00');
CREATE TABLE IF NOT EXISTS core.transacciones_y2026m07 PARTITION OF core.transacciones
    FOR VALUES FROM ('2026-07-01 00:00:00+00') TO ('2026-08-01 00:00:00+00');
CREATE TABLE IF NOT EXISTS core.transacciones_y2026m08 PARTITION OF core.transacciones
    FOR VALUES FROM ('2026-08-01 00:00:00+00') TO ('2026-09-01 00:00:00+00');
