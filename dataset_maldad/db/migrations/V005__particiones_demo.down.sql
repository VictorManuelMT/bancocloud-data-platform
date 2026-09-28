-- =============================================================================
-- V005__particiones_demo.down.sql - Reversa de V005
-- OJO: falla si las particiones contienen filas (hay que archivar primero).
-- OJO 2: NO dropea y2026m09: esa particion le pertenece a la base (existe en la
-- v12 y en el master v13). V005 solo la crea si falta, asi que dropearla aqui
-- dejaria la base peor de como estaba.
-- =============================================================================

DROP TABLE IF EXISTS core.transacciones_y2026m08;
DROP TABLE IF EXISTS core.transacciones_y2026m07;
DROP TABLE IF EXISTS core.transacciones_y2026m06;
DROP TABLE IF EXISTS core.transacciones_y2026m05;
DROP TABLE IF EXISTS core.transacciones_y2026m04;
DROP TABLE IF EXISTS core.transacciones_y2026m03;
DROP TABLE IF EXISTS core.transacciones_y2026m02;
DROP TABLE IF EXISTS core.transacciones_y2026m01;
DROP TABLE IF EXISTS core.transacciones_y2025m12;
DROP TABLE IF EXISTS core.transacciones_y2025m11;
DROP TABLE IF EXISTS core.transacciones_y2025m10;
