-- =============================================================================
-- V005__particiones_demo.sql - Particiones mensuales oct-2025 a sep-2026
-- La ventana demo es 2025-10-01 a 2026-09-30 (12 meses).
-- El master v12 solo trae y2026m09 e y2026m10; aqui se crean las 11 restantes
-- (oct-2025 .. sep-2026), todas con IF NOT EXISTS.
-- Correccion 7.8.1: faltaba sep-2026. Sin ella, instalando migrando desde la
-- v12 la carga revienta en la primera transaccion de septiembre. Se crea igual
-- aunque la base ya la tenga, para que la migracion quede completa por si sola;
-- por eso la reversa NO la dropea (y2026m09 pertenece a la base, no a V005).
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
-- sep-2026: la que faltaba (7.8). Cubre 2026-09-01 .. 2026-09-30, el cierre
-- exacto de la ventana demo.
CREATE TABLE IF NOT EXISTS core.transacciones_y2026m09 PARTITION OF core.transacciones
    FOR VALUES FROM ('2026-09-01 00:00:00+00') TO ('2026-10-01 00:00:00+00');
