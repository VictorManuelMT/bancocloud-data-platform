-- =============================================================================
-- V002__catalogos_seed.down.sql — Reversa de V002 (solo en base vacía/de prueba)
-- Elimina únicamente las filas semilla. No usar si ya hay data operativa.
-- =============================================================================

DELETE FROM reference.productos WHERE producto_id BETWEEN 1 AND 11;
DELETE FROM reference.sucursales WHERE sucursal_id BETWEEN 1 AND 10;
DELETE FROM reference.canales WHERE canal_id BETWEEN 1 AND 7;
-- monedas no se borran: vienen del master v12.
