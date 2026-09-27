-- =============================================================================
-- V004__rls.down.sql — Reversa de V004 (restaura las 2 políticas SELECT de v12)
-- =============================================================================

DROP POLICY IF EXISTS policy_clientes_propios ON core.clientes;
DROP POLICY IF EXISTS policy_cuentas_select ON core.cuentas;
DROP POLICY IF EXISTS policy_cuentas_insert ON core.cuentas;
DROP POLICY IF EXISTS policy_cuentas_update ON core.cuentas;
DROP POLICY IF EXISTS policy_transacciones_select ON core.transacciones;
DROP POLICY IF EXISTS policy_transacciones_insert ON core.transacciones;
DROP POLICY IF EXISTS policy_transacciones_update ON core.transacciones;

CREATE POLICY policy_cuentas_cliente ON core.cuentas
    FOR SELECT
    USING (cliente_id = NULLIF(current_setting('app.current_client_id', true), '')::UUID);

CREATE POLICY policy_transacciones_cliente ON core.transacciones
    FOR SELECT
    USING (
        cuenta_origen_id IN (
            SELECT cuenta_id FROM core.cuentas
            WHERE cliente_id = NULLIF(current_setting('app.current_client_id', true), '')::UUID
        )
    );
